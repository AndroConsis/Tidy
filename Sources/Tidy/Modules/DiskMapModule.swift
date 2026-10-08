import Foundation

/// Measures the Home folder for the Disk Map. Like Large Files, this walks
/// folders rather than a fixed list of paths, so it runs only when the user
/// opens the map and asks for it; it reads sizes only, never file contents.
enum DiskMapModule {
    final class Node: Identifiable {
        let url: URL
        let name: String
        let isDirectory: Bool
        var size: Int64
        /// The biggest children, largest first. nil when this folder was
        /// measured but not broken down yet (loaded when the user opens it).
        var children: [Node]?
        /// Everything in this folder too small to show on its own.
        var otherSize: Int64 = 0
        var otherCount = 0

        var id: URL { url }

        init(url: URL, name: String? = nil, isDirectory: Bool, size: Int64, children: [Node]? = nil) {
            self.url = url
            self.name = name ?? url.lastPathComponent
            self.isDirectory = isDirectory
            self.size = size
            self.children = children
        }
    }

    struct Overview {
        let total: Int64
        let free: Int64
        let apps: Int64
        let home: Int64
        var systemAndOther: Int64 { max(total - free - apps - home, 0) }
    }

    /// Reading other apps' sandboxed data makes macOS ask the user for
    /// permission on every scan, so these are left out of the map.
    static func isSkipped(_ url: URL, home: URL) -> Bool {
        let path = url.path
        return path == home.appendingPathComponent("Library/Containers").path
            || path == home.appendingPathComponent("Library/Group Containers").path
    }

    static let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
    static let maxChildren = 40

    final class Context {
        let home: URL
        let isCancelled: () -> Bool
        let progress: (Int) -> Void
        var visited = 0
        init(home: URL, isCancelled: @escaping () -> Bool, progress: @escaping (Int) -> Void) {
            self.home = home; self.isCancelled = isCancelled; self.progress = progress
        }
        func tick() {
            visited += 1
            if visited % 5000 == 0 { progress(visited) }
        }
    }

    /// Measures `url`, keeping a breakdown `levels` deep; below that only
    /// totals are kept, so memory stays small however many files there are.
    static func measure(_ url: URL, levels: Int, home: URL = FSUtil.home,
                        isCancelled: @escaping () -> Bool = { false },
                        progress: @escaping (Int) -> Void = { _ in }) -> Node {
        let context = Context(home: home, isCancelled: isCancelled, progress: progress)
        let node = measureDirectory(url, levels: levels, context: context)
        progress(context.visited)
        return node
    }

    private static func measureDirectory(_ url: URL, levels: Int, context: Context) -> Node {
        let entries = (try? FSUtil.fm.contentsOfDirectory(at: url, includingPropertiesForKeys: Array(keys), options: [])) ?? []
        var children: [Node] = []
        var total: Int64 = 0
        for entry in entries {
            if context.isCancelled() { break }
            context.tick()
            guard let v = try? entry.resourceValues(forKeys: keys), v.isSymbolicLink != true else { continue }
            if v.isDirectory == true {
                if isSkipped(entry, home: context.home) { continue }
                let child = levels > 1
                    ? measureDirectory(entry, levels: levels - 1, context: context)
                    : Node(url: entry, isDirectory: true, size: totalSize(of: entry, context: context))
                total += child.size
                if child.size > 0 { children.append(child) }
            } else {
                let size = Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
                total += size
                if size > 0 { children.append(Node(url: entry, isDirectory: false, size: size)) }
            }
        }
        children.sort { $0.size > $1.size }
        let node = Node(url: url, isDirectory: true, size: total)
        // Keep the big pieces; anything under 0.5% of this folder is pooled.
        let threshold = total / 200
        let kept = children.prefix(maxChildren).filter { $0.size >= threshold }
        let rest = children.dropFirst(kept.count)
        node.children = Array(kept)
        node.otherSize = rest.reduce(0) { $0 + $1.size }
        node.otherCount = rest.count
        return node
    }

    /// Total allocated size, including inside packages such as a Photos
    /// library (FSUtil.size skips package contents, which a map can't).
    private static func totalSize(of url: URL, context: Context) -> Int64 {
        guard let enumerator = FSUtil.fm.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let entry as URL in enumerator {
            context.tick()
            if context.visited % 2000 == 0 && context.isCancelled() { break }
            guard let v = try? entry.resourceValues(forKeys: keys), v.isSymbolicLink != true else { continue }
            if v.isDirectory == true {
                if isSkipped(entry, home: context.home) { enumerator.skipDescendants() }
                continue
            }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func overview(homeSize: Int64) -> Overview {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        let context = Context(home: FSUtil.home, isCancelled: { false }, progress: { _ in })
        let apps = totalSize(of: URL(fileURLWithPath: "/Applications"), context: context)
        return Overview(
            total: Int64(values?.volumeTotalCapacity ?? 0),
            free: values?.volumeAvailableCapacityForImportantUsage ?? 0,
            apps: apps,
            home: homeSize
        )
    }
}
