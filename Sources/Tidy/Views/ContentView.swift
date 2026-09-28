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
    @State private var selection: Section_? = .overview

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
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

                HStack(spacing: 12) {
                    Button {
                        state.cleanAllRegenerable()
                    } label: {
                        Label("Clean all safe items · \(ByteCountFormatter.string(fromByteCount: state.result.safeAutoCleanBytes, countStyle: .file))", systemImage: "sparkles")
                    }
                    .buttonStyle(.gradientProminent)
                    .disabled(state.result.safeAutoCleanBytes == 0)

                    if state.autoCleanEnabled {
                        Label("Auto-clean on", systemImage: "clock.badge.checkmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.teal)
                    }
                }

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
        }
        .navigationTitle("Overview")
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

    var body: some View {
        GeometryReader { geo in
            let total = max(freeBytes + reclaimableBytes, 1)
            HStack(spacing: 3) {
                Capsule().fill(Theme.warmGradient)
                    .frame(width: max(geo.size.width * CGFloat(reclaimableBytes) / CGFloat(total) - 1.5, 0))
                Capsule().fill(LinearGradient(colors: [Theme.teal, Theme.teal.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(geo.size.width * CGFloat(freeBytes) / CGFloat(total) - 1.5, 0))
            }
        }
        .frame(height: 16)
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
