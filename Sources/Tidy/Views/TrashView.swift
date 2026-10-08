import SwiftUI
import AppKit

/// The user's Trash. Emptying it is the one permanent action in Tidy, so it
/// only ever happens from this button, after a confirmation, and never on a
/// schedule.
@MainActor
final class TrashModel: ObservableObject {
    @Published var sizeBytes: Int64 = 0
    @Published var itemCount = 0
    /// False when macOS doesn't let Tidy look inside the Trash.
    @Published var isReadable = true
    @Published var isWorking = false
    #if DEBUG
    /// Screenshot mode shows sample numbers instead of this Mac's Trash.
    var isSample = false
    #endif

    var url: URL { FSUtil.home.appendingPathComponent(".Trash", isDirectory: true) }

    func refresh() {
        #if DEBUG
        if isSample { return }
        #endif
        let url = url
        Task.detached(priority: .utility) { [weak self] in
            let entries = try? FSUtil.fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])
            let visible = (entries ?? []).filter { $0.lastPathComponent != ".DS_Store" }
            let size = visible.reduce(Int64(0)) { $0 + FSUtil.size(of: $1, includingPackages: true) }
            await MainActor.run { [weak self] in
                self?.isReadable = entries != nil
                self?.itemCount = visible.count
                self?.sizeBytes = size
            }
        }
    }

    /// Permanently deletes everything in the Trash. Returns bytes freed.
    func empty() async -> Int64 {
        isWorking = true
        let url = url
        let (freed, count) = await Task.detached(priority: .userInitiated) { () -> (Int64, Int) in
            let entries = (try? FSUtil.fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [])) ?? []
            var freed: Int64 = 0
            var count = 0
            for entry in entries where entry.lastPathComponent != ".DS_Store" {
                let size = FSUtil.size(of: entry, includingPackages: true)
                if (try? FSUtil.fm.removeItem(at: entry)) != nil {
                    freed += size
                    count += 1
                }
            }
            return (freed, count)
        }.value
        if count > 0 {
            ActionLog.append(LogEntry(date: Date(), name: "Emptied the Trash (\(count) item\(count == 1 ? "" : "s"))",
                                      paths: [url.path], sizeBytes: freed, category: "Trash"))
        }
        isWorking = false
        refresh()
        return freed
    }
}

struct TrashView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: TrashModel
    @State private var confirming = false

    private var sizeText: String { ByteCountFormatter.string(fromByteCount: model.sizeBytes, countStyle: .file) }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: model.itemCount > 0 ? "trash.fill" : "trash")
                .font(.system(size: 46))
                .foregroundStyle(Theme.accentGradient)
            if !model.isReadable {
                Text("macOS keeps the Trash private").font(.system(size: 16, weight: .semibold, design: .rounded))
                Text("To size and empty it here, turn on Tidy in Full Disk Access, then come back. Or empty it from Finder.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                HStack(spacing: 10) {
                    Button("Open Trash in Finder") { NSWorkspace.shared.open(model.url) }
                    Button("Open Full Disk Access…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.gradientProminent)
                }
            } else if model.itemCount == 0 {
                Text("The Trash is empty").font(.system(size: 16, weight: .semibold, design: .rounded))
            } else {
                Text(sizeText).font(.system(size: 30, weight: .bold, design: .rounded))
                Text("\(model.itemCount) item\(model.itemCount == 1 ? "" : "s") in the Trash, including anything Tidy moved there.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("Show in Finder") { NSWorkspace.shared.open(model.url) }
                    Button {
                        confirming = true
                    } label: {
                        Label("Empty Trash…", systemImage: "trash")
                    }
                    .buttonStyle(.gradientProminent)
                    .disabled(model.isWorking)
                }
                if model.isWorking { ProgressView().controlSize(.small) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
        .alert("Empty the Trash?", isPresented: $confirming) {
            Button("Empty Trash", role: .destructive) {
                Task {
                    let freed = await model.empty()
                    state.recentActions = ActionLog.read()
                    Feedback.requestReviewIfEarned(freedBytes: freed)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.itemCount) item\(model.itemCount == 1 ? "" : "s") (\(sizeText)) will be deleted permanently. You can't undo this.")
        }
    }
}
