import SwiftUI

enum Section_: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case xcode = "Xcode"
    case devCaches = "Dev Caches"
    case appCaches = "App Caches"
    case installers = "Installers"
    case unusedApps = "Unused Apps"
    case system = "System"
    case settings = "Settings"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .xcode: return "hammer.fill"
        case .devCaches: return "shippingbox.fill"
        case .appCaches: return "internaldrive.fill"
        case .installers: return "arrow.down.circle.fill"
        case .unusedApps: return "app.dashed"
        case .system: return "wand.and.stars"
        case .settings: return "gearshape.fill"
        }
    }

    /// Each icon gets its own accent, the way macOS's own Reminders/Mail
    /// sidebar does — it makes the list scannable at a glance.
    var tint: Color {
        switch self {
        case .overview: return Theme.violet
        case .xcode: return .indigo
        case .devCaches: return .orange
        case .appCaches: return .pink
        case .installers: return .blue
        case .unusedApps: return .gray
        case .system: return Theme.teal
        case .settings: return .secondary
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: Section_?

    init(initialSelection: Section_ = .overview) {
        _selection = State(initialValue: initialSelection)
    }

    var body: some View {
        NavigationSplitView {
            List(Section_.allCases, selection: $selection) { section in
                Label {
                    Text(section.rawValue)
                } icon: {
                    Image(systemName: section.icon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(section.tint)
                }
                .tag(section)
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
        .frame(minWidth: 720, minHeight: 480)
        .alert("Error", isPresented: .constant(state.lastError != nil), actions: {
            Button("OK") { state.lastError = nil }
        }, message: { Text(state.lastError ?? "") })
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .overview {
        case .overview: OverviewView()
        case .xcode: CategoryListView(title: "Xcode", items: state.result.xcodeDeviceSupport + state.result.xcodeSimulators + state.result.xcodeBuildData)
        case .devCaches: CategoryListView(title: "Dev Caches", items: state.result.devCaches)
        case .appCaches: CategoryListView(title: "App Caches", items: state.result.appCaches)
        case .installers: CategoryListView(title: "Installers", items: state.result.installers)
        case .unusedApps: CategoryListView(title: "Unused Apps", items: state.result.unusedApps)
        case .system: CategoryListView(title: "System", items: state.result.system)
        case .settings: SettingsView()
        }
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
                            Text("Most caches and Xcode data live there. Choose your Home folder once so scans can reach them.")
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
