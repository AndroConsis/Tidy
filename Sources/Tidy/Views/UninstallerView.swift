import SwiftUI
import AppKit

@MainActor
final class UninstallerModel: ObservableObject {
    typealias App = UninstallerModule.InstalledApp

    @Published var apps: [App] = []
    @Published var isLoading = false
    @Published var hasLoaded = false

    func load() {
        guard !isLoading else { return }
        isLoading = true
        Task.detached(priority: .userInitiated) { [weak self] in
            let listed = UninstallerModule.installedApps()
            await MainActor.run { [weak self] in
                self?.apps = listed
                self?.hasLoaded = true
            }
            // Sizes take longer; fill them in once everything is listed.
            let sized = listed.map { app -> UninstallerModule.InstalledApp in
                var app = app
                app.sizeBytes = FSUtil.size(of: app.url, includingPackages: true)
                return app
            }
            await MainActor.run { [weak self] in
                self?.apps = sized
                self?.isLoading = false
            }
        }
    }

    enum Outcome {
        case removed(Int64)
        /// macOS wouldn't let Tidy move the app, so it's shown in Finder.
        case needsFinder(String)
        case failed(String)
    }

    /// Moves the app to the Trash first; its leftovers follow only if that
    /// worked, so a failed attempt never leaves an app without its settings.
    func uninstall(_ app: App, leftovers: [UninstallerModule.Leftover]) async -> Outcome {
        guard !UninstallerModule.isRunning(app) else { return .failed("Quit \(app.name) first, then try again.") }
        do {
            _ = try await NSWorkspace.shared.recycle([app.url])
        } catch {
            NSWorkspace.shared.activateFileViewerSelecting([app.url])
            return .needsFinder(app.isFromAppStore
                ? "\(app.name) came from the App Store, so macOS asks you to remove it yourself. It's selected in Finder: drag it to the Trash, or hold it in Launchpad and click ×. Then come back to remove its leftover files."
                : "macOS didn't let Tidy move \(app.name). It's selected in Finder: drag it to the Trash, then come back to remove its leftover files.")
        }
        var freed = app.sizeBytes
        var failures: [String] = []
        for leftover in leftovers {
            do {
                try FSUtil.trash(leftover.url.path)
                freed += leftover.sizeBytes
            } catch {
                failures.append(leftover.url.lastPathComponent)
            }
        }
        ActionLog.append(LogEntry(date: Date(), name: "Uninstalled \(app.name)",
                                  paths: [app.url.path] + leftovers.map(\.url.path),
                                  sizeBytes: freed, category: ItemCategory.uninstalledApp.rawValue))
        apps.removeAll { $0.id == app.id }
        if !failures.isEmpty {
            return .failed("\(app.name) was moved to the Trash, but these couldn't be: \(failures.joined(separator: ", ")).")
        }
        return .removed(freed)
    }

    /// For an app the user already deleted in Finder: just its leftovers.
    func removeLeftovers(_ leftovers: [UninstallerModule.Leftover], appName: String) -> Int64 {
        var freed: Int64 = 0
        for leftover in leftovers where (try? FSUtil.trash(leftover.url.path)) != nil { freed += leftover.sizeBytes }
        if freed > 0 {
            ActionLog.append(LogEntry(date: Date(), name: "Leftovers of \(appName)", paths: leftovers.map(\.url.path),
                                      sizeBytes: freed, category: ItemCategory.uninstalledApp.rawValue))
        }
        return freed
    }
}

struct UninstallerView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: UninstallerModel
    @ObservedObject private var folderAccess = FolderAccess.shared
    @State private var search = ""
    @State private var sort: Sort = .size
    @State private var unusedOnly = false
    static let unusedDays = 90
    @State private var selected: UninstallerModule.InstalledApp?

    enum Sort: String, CaseIterable, Identifiable {
        case size = "Size", name = "Name", lastOpened = "Last Opened"
        var id: String { rawValue }
    }

    private var visibleApps: [UninstallerModule.InstalledApp] {
        let filtered = model.apps.filter { app in
            (search.isEmpty || app.name.localizedCaseInsensitiveContains(search))
                && (!unusedOnly || FSUtil.daysSince(app.lastOpened) >= Self.unusedDays)
        }
        switch sort {
        case .size: return filtered.sorted { $0.sizeBytes > $1.sizeBytes }
        case .name: return filtered
        case .lastOpened: return filtered.sorted { ($0.lastOpened ?? .distantPast) < ($1.lastOpened ?? .distantPast) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                if !folderAccess.hasApplicationsAccess {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.open").font(.system(size: 20)).foregroundStyle(Theme.amber)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Allow Tidy to remove apps").font(.system(size: 13, weight: .semibold))
                            Text("Grant the Applications folder once. Until then, Tidy shows apps in Finder.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Grant Access…") { folderAccess.requestApplicationsAccess() }
                    }
                    .padding(14)
                    .background(Theme.cardBackground())
                }
                HStack {
                    TextField("Search apps", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                    Picker("", selection: $unusedOnly) {
                        Text("All Apps").tag(false)
                        Text("Unused 3+ Months").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                    Picker("Sort by", selection: $sort) {
                        ForEach(Sort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 200)
                    Spacer()
                    if model.isLoading { ProgressView().controlSize(.small) }
                }
            }
            .padding(20)
            Divider()
            if !model.hasLoaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visibleApps) { app in
                    AppRow(app: app) { selected = app }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle("Apps")
        .onAppear { if !model.hasLoaded { model.load() } }
        .sheet(item: $selected) { app in
            UninstallSheet(app: app, model: model) { freed in
                state.recentActions = ActionLog.read()
                if freed > 0 {
                    Feedback.requestReviewIfEarned(freedBytes: freed)
                    Task { await state.scan() }
                }
            }
        }
    }
}

struct AppRow: View {
    let app: UninstallerModule.InstalledApp
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                .resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.name).font(.system(size: 13, weight: .medium))
                    if let version = app.version {
                        Text(version).font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                Text(app.lastOpened.map { "Opened \($0.formatted(.relative(presentation: .named)))" } ?? "No record of being opened")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if app.sizeBytes > 0 {
                Text(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file))
                    .font(.system(size: 13, weight: .semibold))
            }
            Button("Uninstall…", action: onUninstall)
                .controlSize(.small)
                .tint(Theme.amber)
        }
        .padding(.vertical, 3)
    }
}

/// Shows exactly what will go to the Trash, with every leftover file listed
/// and individually untickable, before anything is removed.
struct UninstallSheet: View {
    let app: UninstallerModule.InstalledApp
    @ObservedObject var model: UninstallerModel
    let onFinished: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var leftovers: [UninstallerModule.Leftover] = []
    @State private var included: Set<URL> = []
    @State private var isWorking = false
    @State private var message: String?
    @State private var appGone = false
    @State private var watcher: Task<Void, Never>?

    private var chosen: [UninstallerModule.Leftover] { leftovers.filter { included.contains($0.url) } }
    private var total: Int64 { (appGone ? 0 : app.sizeBytes) + chosen.reduce(0) { $0 + $1.sizeBytes } }
    private var isRunning: Bool { UninstallerModule.isRunning(app) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Uninstall \(app.name)?").font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("Everything ticked below goes to the Trash, so you can put it back until you empty it.")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "checkmark.square.fill").foregroundStyle(Theme.violet)
                    Text("\(app.name).app").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: app.sizeBytes, countStyle: .file)).font(.system(size: 12))
                }
                .opacity(appGone ? 0.4 : 1)
                if leftovers.isEmpty {
                    Text("No leftover files found in your Library.").font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    Text("Leftover files in your Library").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        .padding(.top, 4)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(leftovers) { leftover in
                                Toggle(isOn: Binding(
                                    get: { included.contains(leftover.url) },
                                    set: { if $0 { included.insert(leftover.url) } else { included.remove(leftover.url) } }
                                )) {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(leftover.kind).font(.system(size: 12))
                                            Text("~/Library/" + leftover.url.path.components(separatedBy: "/Library/").dropFirst().joined(separator: "/Library/"))
                                                .font(.system(size: 10)).foregroundStyle(.secondary)
                                                .lineLimit(1).truncationMode(.middle)
                                        }
                                        Spacer()
                                        Text(ByteCountFormatter.string(fromByteCount: leftover.sizeBytes, countStyle: .file)).font(.system(size: 12))
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
            }
            .padding(12)
            .background(Theme.cardBackground(cornerRadius: 10))

            if let message {
                Text(message).font(.system(size: 12)).foregroundStyle(Theme.amber)
                    .fixedSize(horizontal: false, vertical: true)
            } else if isRunning {
                Text("\(app.name) is open. Quit it first, then uninstall.").font(.system(size: 12)).foregroundStyle(Theme.amber)
            }

            HStack {
                Text("Total: \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                if appGone {
                    Button("Remove Leftovers") {
                        onFinished(model.removeLeftovers(chosen, appName: app.name))
                        dismiss()
                    }
                    .disabled(chosen.isEmpty)
                } else {
                    Button("Move to Trash", role: .destructive) {
                        isWorking = true
                        Task {
                            let outcome = await model.uninstall(app, leftovers: chosen)
                            isWorking = false
                            switch outcome {
                            case .removed(let freed):
                                onFinished(freed)
                                dismiss()
                            case .needsFinder(let text):
                                message = text
                                watchForRemoval()
                            case .failed(let text):
                                message = text
                                onFinished(0)
                            }
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || isRunning)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
        .onDisappear { watcher?.cancel() }
        .onAppear {
            leftovers = UninstallerModule.leftovers(for: app)
            included = Set(leftovers.map(\.url))
        }
    }

    /// After the user removes the app in Finder, offer its leftovers.
    private func watchForRemoval() {
        watcher = Task {
            while !appGone && !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if !FSUtil.exists(app.url.path) {
                    appGone = true
                    message = "\(app.name) is in the Trash. You can now remove its leftover files."
                    model.apps.removeAll { $0.id == app.id }
                }
            }
        }
    }
}
