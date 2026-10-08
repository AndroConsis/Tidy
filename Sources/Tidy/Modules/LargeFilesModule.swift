import Foundation
import UniformTypeIdentifiers

/// Finds big files the user made or downloaded themselves. Unlike every other
/// module this walks folders rather than a fixed list of paths, so it only
/// runs when the user starts it, its results never count towards
/// "Reclaimable", and nothing it finds is ever cleaned automatically.
enum LargeFilesModule {
    struct LargeFile: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let sizeBytes: Int64
        let lastOpened: Date?
        let lastModified: Date?
        let kind: String
        /// Stored in iCloud Drive: removing it removes it on every device.
        let isInICloud: Bool

        var lastUsed: Date? { lastOpened ?? lastModified }
    }

    /// Folders that belong to macOS, apps or developer tools; other sections
    /// already cover the parts of them that are safe to remove.
    static let skippedTopLevel: Set<String> = ["Library", "Applications", ".Trash"]
    static let skippedFolderNames: Set<String> = ["node_modules", "Pods", "DerivedData", "Carthage"]

    /// Walks the Home folder for files of at least `minBytes`. Packages such
    /// as a Photos library, an app or a Final Cut library are never entered
    /// or listed: they look like one file but are managed by their own app.
    static func scan(home: URL = FSUtil.home, minBytes: Int64,
                     isCancelled: () -> Bool = { false },
                     progress: (Int) -> Void = { _ in }) -> [LargeFile] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey,
                                      .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        let roots = ((try? FSUtil.fm.contentsOfDirectory(at: home, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? [])
            .filter { !skippedTopLevel.contains($0.lastPathComponent) }

        var found: [URL: Int64] = [:]
        var visited = 0
        for root in roots {
            if isCancelled() { break }
            guard let vals = try? root.resourceValues(forKeys: Set(keys)), vals.isSymbolicLink != true else { continue }
            if vals.isDirectory != true {
                let size = Int64(vals.totalFileAllocatedSize ?? vals.fileAllocatedSize ?? 0)
                if size >= minBytes { found[root] = size }
                continue
            }
            if vals.isPackage == true { continue }
            guard let enumerator = FSUtil.fm.enumerator(
                at: root, includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants],
                errorHandler: { _, _ in true }
            ) else { continue }

            for case let url as URL in enumerator {
                visited += 1
                if visited % 2000 == 0 {
                    if isCancelled() { break }
                    progress(visited)
                }
                guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true else { continue }
                if v.isDirectory == true {
                    if v.isPackage == true || skippedFolderNames.contains(url.lastPathComponent) {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                // Allocated size, so iCloud files that are only stored in the
                // cloud (and take no space here) aren't listed.
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                if size >= minBytes { found[url] = size }
            }
        }
        progress(visited)

        return found.map { url, size in
            let meta = (try? url.resourceValues(forKeys: [.contentModificationDateKey, .localizedTypeDescriptionKey, .isUbiquitousItemKey]))
            return LargeFile(
                url: url, sizeBytes: size,
                lastOpened: lastOpenedDate(url),
                lastModified: meta?.contentModificationDate,
                kind: meta?.localizedTypeDescription ?? url.pathExtension.uppercased(),
                isInICloud: meta?.isUbiquitousItem == true
            )
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Spotlight records when a file was last opened; the raw access time is
    /// bumped by backups and indexing, so it isn't used.
    static func lastOpenedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}
