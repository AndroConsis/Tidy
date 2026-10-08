import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Holds Large Files results across sidebar switches. Kept apart from
/// ScanResult so these personal files never count as "Reclaimable" and can
/// never be picked up by "Clean all safe items" or auto-clean.
@MainActor
final class LargeFilesModel: ObservableObject {
    @Published var files: [LargeFilesModule.LargeFile] = []
    @Published var isScanning = false
    @Published var visitedCount = 0
    @Published var lastScanDate: Date?
    @Published var minBytes: Int64 = 500_000_000
    /// A folder chosen from the Disk Map; nil searches the whole Home folder.
    @Published var scope: URL?
    private var cancelled = false

    func search(in folder: URL?) {
        scope = folder
        files = []
        lastScanDate = nil
        scan()
    }

    func scan() {
        guard !isScanning else { return }
        let scope = scope
        isScanning = true
        cancelled = false
        visitedCount = 0
        Task.detached(priority: .utility) { [weak self] in
            let files = LargeFilesModule.scan(
                // Always gather everything over 100 MB; the size picker
                // just filters, so changing it doesn't need a new search.
                root: scope,
                minBytes: 100_000_000,
                isCancelled: { [weak self] in
                    guard let self else { return true }
                    return DispatchQueue.main.sync { self.cancelled }
                },
                progress: { [weak self] count in
                    DispatchQueue.main.async { self?.visitedCount = count }
                }
            )
            await MainActor.run { [weak self] in
                guard let self else { return }
                if !self.cancelled { self.files = files; self.lastScanDate = Date() }
                self.isScanning = false
            }
        }
    }

    func cancel() { cancelled = true }

    func moveToTrash(_ file: LargeFilesModule.LargeFile) throws {
        try FSUtil.trash(file.url.path)
        ActionLog.append(LogEntry(date: Date(), name: file.url.lastPathComponent, paths: [file.url.path],
                                  sizeBytes: file.sizeBytes, category: ItemCategory.largeFile.rawValue))
        files.removeAll { $0.id == file.id }
    }
}

struct LargeFilesView: View {
    @EnvironmentObject var state: AppState
    @ObservedObject var model: LargeFilesModel
    @State private var notOpenedFor: AgeFilter = .any
    @State private var pendingTrash: LargeFilesModule.LargeFile?

    enum AgeFilter: Int, CaseIterable, Identifiable {
        case any = 0, threeMonths = 90, sixMonths = 180, year = 365
        var id: Int { rawValue }
        var label: String {
            switch self {
            case .any: return "Any time"
            case .threeMonths: return "3+ months ago"
            case .sixMonths: return "6+ months ago"
            case .year: return "A year+ ago"
            }
        }
    }

    private static let sizeOptions: [(String, Int64)] = [("100 MB", 100_000_000), ("500 MB", 500_000_000), ("1 GB", 1_000_000_000), ("5 GB", 5_000_000_000)]

    private var visibleFiles: [LargeFilesModule.LargeFile] {
        model.files.filter { file in
            file.sizeBytes >= model.minBytes
                && (notOpenedFor == .any || FSUtil.daysSince(file.lastUsed) >= notOpenedFor.rawValue)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(20)
            Divider()
            content
        }
        .navigationTitle("Large Files")
        .confirmationDialog(
            pendingTrash.map { "Move \u{201C}\($0.url.lastPathComponent)\u{201D} to the Trash?" } ?? "",
            isPresented: .constant(pendingTrash != nil),
            presenting: pendingTrash
        ) { file in
            Button("Move to Trash", role: .destructive) {
                do { try model.moveToTrash(file) } catch {
                    state.lastError = "Couldn't move \(file.url.lastPathComponent) to the Trash: \(error.localizedDescription)"
                }
                state.recentActions = ActionLog.read()
                pendingTrash = nil
            }
            Button("Cancel", role: .cancel) { pendingTrash = nil }
        } message: { file in
            Text(file.isInICloud
                 ? "This file is in iCloud Drive, so it will also be removed from your other devices. You can put it back from the Trash."
                 : "You can put it back from the Trash until you empty it.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Find big files you may have forgotten — old downloads, videos, disk images and archives in your Home folder. Tidy only lists them; nothing is removed unless you choose it.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
            if let scope = model.scope {
                HStack(spacing: 8) {
                    Label("Searching in ~\(scope.path.dropFirst(FSUtil.home.path.count))", systemImage: "folder")
                        .font(.system(size: 12, weight: .medium))
                    Button("Search Whole Home Folder") { model.search(in: nil) }
                        .controlSize(.small)
                        .disabled(model.isScanning)
                }
            }
            HStack(spacing: 14) {
                Picker("Larger than", selection: $model.minBytes) {
                    ForEach(Self.sizeOptions, id: \.1) { Text($0.0).tag($0.1) }
                }
                .frame(width: 180)
                Picker("Last opened", selection: $notOpenedFor) {
                    ForEach(AgeFilter.allCases) { Text($0.label).tag($0) }
                }
                .frame(width: 220)
                Spacer()
                if model.isScanning {
                    ProgressView().controlSize(.small)
                    Button("Stop") { model.cancel() }
                } else {
                    Button {
                        model.scan()
                    } label: {
                        Label(model.lastScanDate == nil ? "Find Large Files" : "Search Again", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.gradientProminent)
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if model.isScanning && model.files.isEmpty {
            VStack(spacing: 8) {
                ProgressView()
                Text("Looked at \(model.visitedCount.formatted()) files…").font(.system(size: 12)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.lastScanDate == nil {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accentGradient)
                Text("Search your Home folder for files larger than \(ByteCountFormatter.string(fromByteCount: model.minBytes, countStyle: .file)).")
                    .foregroundStyle(.secondary)
                Text("Your Library, apps, and libraries such as Photos are skipped.")
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if visibleFiles.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accentGradient)
                Text("No files match these filters").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(visibleFiles) { file in
                LargeFileRow(file: file, onTrash: { pendingTrash = file })
            }
            .listStyle(.inset)
        }
    }
}

struct LargeFileRow: View {
    let file: LargeFilesModule.LargeFile
    let onTrash: () -> Void

    private var homeRelativePath: String {
        let home = FSUtil.home.path
        let dir = file.url.deletingLastPathComponent().path
        return dir.hasPrefix(home) ? "~" + dir.dropFirst(home.count) : dir
    }

    private var usedText: String {
        if let opened = file.lastOpened { return "Opened \(opened.formatted(.relative(presentation: .named)))" }
        if let modified = file.lastModified { return "Never opened · added \(modified.formatted(.relative(presentation: .named)))" }
        return "Never opened"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(for: UTType(filenameExtension: file.url.pathExtension) ?? .data))
                .resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(file.url.lastPathComponent).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    SafetyBadge(safety: .review)
                    if file.isInICloud {
                        Image(systemName: "icloud").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
                Text(homeRelativePath)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                Text("\(file.kind) · \(usedText)")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(ByteCountFormatter.string(fromByteCount: file.sizeBytes, countStyle: .file))
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 6) {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([file.url])
                    }
                    Button("Move to Trash…", action: onTrash)
                        .tint(Theme.amber)
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
