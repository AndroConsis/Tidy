import SwiftUI

/// Sidebar destinations. Related scans share one destination and are split
/// into tabs inside it, so the sidebar stays short.
enum Section_: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case diskMap = "Disk Map"
    case largeFiles = "Large Files"
    case junk = "Junk Files"
    case developer = "Developer"
    case apps = "Apps"
    case settings = "Settings"
    var id: String { rawValue }

    static let storage: [Section_] = [.overview, .diskMap, .largeFiles]
    static let cleanUp: [Section_] = [.junk, .developer, .apps]

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .diskMap: return "square.grid.3x3.square"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .junk: return "trash.fill"
        case .developer: return "hammer.fill"
        case .apps: return "square.grid.2x2.fill"
        case .settings: return "gearshape.fill"
        }
    }

    /// Each icon gets its own accent, the way macOS's own Reminders/Mail
    /// sidebar does — it makes the list scannable at a glance.
    var tint: Color {
        switch self {
        case .overview: return Theme.violet
        case .diskMap: return .cyan
        case .largeFiles: return .purple
        case .junk: return .pink
        case .developer: return .indigo
        case .apps: return .blue
        case .settings: return .secondary
        }
    }

    var tabs: [SubTab] {
        switch self {
        case .junk: return [.appCaches, .installers, .trash, .system]
        case .developer: return [.xcode, .android, .packageCaches]
        default: return []
        }
    }

    /// Where an item found by the scan is listed.
    static func forCategory(_ category: ItemCategory) -> (Section_, SubTab?) {
        switch category {
        case .xcodeDeviceSupport, .xcodeSimulatorRuntime, .xcodeSimulatorDevice, .xcodeSimulatorCache,
             .xcodeDerivedData, .xcodePreviews, .xcodeDocumentation, .xcodeArchive: return (.developer, .xcode)
        case .androidEmulator, .androidSystemImage, .androidCache: return (.developer, .android)
        case .devCache: return (.developer, .packageCaches)
        case .appCache, .orphanedSupport: return (.junk, .appCaches)
        case .installer: return (.junk, .installers)
        case .system: return (.junk, .system)
        case .unusedApp, .uninstalledApp: return (.apps, nil)
        case .largeFile: return (.largeFiles, nil)
        }
    }
}

/// Tabs inside a grouped sidebar destination.
enum SubTab: String, CaseIterable, Identifiable {
    case xcode = "Xcode"
    case android = "Android"
    case packageCaches = "Package Caches"
    case appCaches = "App Caches"
    case installers = "Installers"
    case trash = "Trash"
    case system = "System"
    var id: String { rawValue }

    @MainActor
    func items(in result: ScanResult) -> [CleanableItem] {
        switch self {
        case .xcode: return result.xcodeDeviceSupport + result.xcodeSimulators + result.xcodeBuildData
        case .android: return result.android
        case .packageCaches: return result.devCaches
        case .appCaches: return result.appCaches
        case .installers: return result.installers
        case .system: return result.system
        case .trash: return []
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: Section_?
    @State private var tabs: [Section_: SubTab] = [:]

    init(initialSelection: Section_ = .overview, initialTab: SubTab? = nil) {
        _selection = State(initialValue: initialSelection)
        if let initialTab { _tabs = State(initialValue: [initialSelection: initialTab]) }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                SwiftUI.Section("Storage") {
                    ForEach(Section_.storage) { sidebarRow($0) }
                }
                SwiftUI.Section("Clean Up") {
                    ForEach(Section_.cleanUp) { sidebarRow($0) }
                }
                SwiftUI.Section {
                    sidebarRow(.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(190)
        } detail: {
            detail
                .toolbar {
                    ToolbarItem {
                        Button {
                            Task { await state.scan() }
                        } label: {
                            if state.isScanning {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Rescan", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(state.isScanning)
                    }
                }
        }
        .frame(minWidth: 900, minHeight: 560)
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: .demoSelectSection)) { note in
            if let section = note.object as? Section_ { selection = section }
            if let (section, tab) = note.object as? (Section_, SubTab) { selection = section; tabs[section] = tab }
        }
        #endif
        .alert("Error", isPresented: .constant(state.lastError != nil), actions: {
            Button("OK") { state.lastError = nil }
        }, message: { Text(state.lastError ?? "") })
    }

    private func sidebarRow(_ section: Section_) -> some View {
        Label {
            Text(section.rawValue)
        } icon: {
            Image(systemName: section.icon)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(section.tint)
        }
        .tag(section)
    }

    private func open(_ section: Section_, _ tab: SubTab?) {
        selection = section
        if let tab { tabs[section] = tab }
    }

    private func tabBinding(_ section: Section_) -> Binding<SubTab> {
        Binding(get: { tabs[section] ?? section.tabs[0] }, set: { tabs[section] = $0 })
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .overview {
        case .overview: OverviewView()
        case .diskMap: DiskMapView(model: state.diskMap, openSection: open)
        case .largeFiles: LargeFilesView(model: state.largeFiles)
        case .junk: TabbedCategoryView(section: .junk, tab: tabBinding(.junk))
        case .developer: TabbedCategoryView(section: .developer, tab: tabBinding(.developer))
        case .apps: UninstallerView(model: state.uninstaller)
        case .settings: SettingsView()
        }
    }
}

/// A grouped destination: a segmented tab bar, each tab with its size.
struct TabbedCategoryView: View {
    let section: Section_
    @Binding var tab: SubTab
    @EnvironmentObject var state: AppState

    private func size(_ tab: SubTab) -> Int64 {
        tab == .trash ? state.trash.sizeBytes : tab.items(in: state.result).reduce(0) { $0 + $1.sizeBytes }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(section.tabs) { tab in
                    let bytes = size(tab)
                    Text(bytes > 0 ? "\(tab.rawValue)  \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))" : tab.rawValue)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            if tab == .trash {
                TrashView(model: state.trash)
            } else {
                CategoryListView(title: section.rawValue, items: tab.items(in: state.result))
            }
        }
        .navigationTitle(section.rawValue)
    }
}

struct OverviewView: View {
    @EnvironmentObject var state: AppState

    @ObservedObject private var folderAccess = FolderAccess.shared

    /// Drives a slight fade/rise-in for the whole overview on first appearance.
    @State private var hasAppeared = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !folderAccess.hasHomeAccess {
                    HStack(spacing: 12) {
                        Image(systemName: "folder.badge.questionmark")
                            .font(.system(size: 22))
                            .foregroundStyle(Theme.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Tidy can't see your Home folder yet").font(.system(size: 13, weight: .semibold))
                            Text("Grant it once so Tidy can find caches and junk.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Grant Access…") {
                            if folderAccess.requestHomeAccess() { Task { await state.scan() } }
                        }
                    }
                    .padding(14)
                    .background(Theme.cardBackground())
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Storage").font(.system(size: 20, weight: .bold, design: .rounded))
                        Spacer()
                        if let last = state.lastScanDate {
                            Text("Scanned \(last.formatted(.relative(presentation: .named)))")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    DiskBar(freeBytes: state.freeBytes, reclaimableBytes: state.result.reclaimableBytes)
                    HStack(spacing: 16) {
                        Legend(color: Theme.teal, label: "Free", value: state.freeBytes)
                        Legend(color: Theme.amber, label: "Reclaimable", value: state.result.reclaimableBytes)
                    }
                }
                .padding(16)
                .background(Theme.cardBackground())

                CleanActionRow()

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recent Activity").font(.system(size: 14, weight: .semibold, design: .rounded))
                    if state.recentActions.isEmpty {
                        Text("Nothing cleaned yet.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(state.recentActions.prefix(8)) { entry in
                                HStack {
                                    Text(entry.name).font(.system(size: 12))
                                    Spacer()
                                    Text(ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Theme.teal)
                                    Text(entry.date.formatted(.relative(presentation: .named)))
                                        .font(.system(size: 11))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
                .padding(16)
                .background(Theme.cardBackground())
            }
            .padding(20)
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 8)
        }
        .navigationTitle("Overview")
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                hasAppeared = true
            }
        }
    }
}

/// The primary "Clean all safe items" action, plus the states around it:
/// mid-scan, nothing found, and items that exist but need a manual review
/// click instead of being silently lumped into "0 bytes".
struct CleanActionRow: View {
    @EnvironmentObject var state: AppState

    private var reviewCount: Int {
        state.result.all.filter { $0.safety == .review }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            if state.isScanning && state.lastScanDate == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Scanning your Mac…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else if state.result.safeAutoCleanBytes > 0 {
                Button {
                    state.cleanAllRegenerable()
                } label: {
                    Label("Clean all safe items · \(ByteCountFormatter.string(fromByteCount: state.result.safeAutoCleanBytes, countStyle: .file))", systemImage: "sparkles")
                }
                .buttonStyle(.gradientProminent)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.teal)
                    Text(reviewCount > 0
                        ? "Nothing safe to auto-clean — \(reviewCount) item\(reviewCount == 1 ? "" : "s") could use a quick look."
                        : "You're all tidy — nothing safe to auto-clean right now."
                    )
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            if state.autoCleanEnabled {
                Label("Auto-clean on", systemImage: "clock.badge.checkmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.teal)
            }
        }
    }
}

struct Legend: View {
    let color: Color
    let label: String
    let value: Int64
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
            Text(ByteCountFormatter.string(fromByteCount: value, countStyle: .file))
                .font(.system(size: 12, weight: .semibold))
        }
    }
}

struct DiskBar: View {
    let freeBytes: Int64
    let reclaimableBytes: Int64

    /// Drives the fill-in-from-nothing animation on first appearance.
    @State private var hasAppeared = false

    var body: some View {
        GeometryReader { geo in
            let total = max(freeBytes + reclaimableBytes, 1)
            let reclaimableFraction = hasAppeared ? CGFloat(reclaimableBytes) / CGFloat(total) : 0
            let freeFraction = hasAppeared ? CGFloat(freeBytes) / CGFloat(total) : 0

            // A single outer-rounded track holds both segments flush against
            // each other, so the only curves are at the far left/right edges
            // — the seam where reclaimable meets free stays a clean straight
            // line instead of two inner curves butting up against each other.
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.05))

                HStack(spacing: 0) {
                    Rectangle().fill(Theme.warmGradient)
                        .frame(width: geo.size.width * reclaimableFraction)
                    Rectangle().fill(LinearGradient(colors: [Theme.teal, Theme.teal.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * freeFraction)
                    Spacer(minLength: 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .animation(.easeInOut(duration: 0.7), value: reclaimableBytes)
            .animation(.easeInOut(duration: 0.7), value: freeBytes)
        }
        .frame(height: 16)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9).delay(0.1)) {
                hasAppeared = true
            }
        }
    }
}

struct CategoryListView: View {
    let title: String
    let items: [CleanableItem]
    @EnvironmentObject var state: AppState

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(Theme.accentGradient)
                    Text("Nothing found here").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(items.sorted { $0.sizeBytes > $1.sizeBytes }) { item in
                    ItemRowView(item: item) { state.clean($0) }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(title)
    }
}
