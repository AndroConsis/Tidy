import Foundation

/// General ~/Library/Caches contents, auto-updater leftovers, and
/// Application Support folders that belong to apps no longer installed.
enum AppCachesModule {
    static let home = FSUtil.home

    // Folders in ~/Library/Caches we never touch even if large: they belong
    // to system services or things Tidy can't safely reason about.
    static let protectedCacheNames: Set<String> = [
        "CloudKit", "com.apple.helpd", "com.apple.Spotlight", "GeoServices",
        "com.apple.akd", "com.apple.corespotlightservice",
    ]

    static func scanGeneralCaches() -> [CleanableItem] {
        let dir = home.appendingPathComponent("Library/Caches")
        let subfolders = FSUtil.subdirectories(of: dir.path)
        var items: [CleanableItem] = []

        for folder in subfolders {
            let name = folder.lastPathComponent
            guard !protectedCacheNames.contains(name) else { continue }
            let size = FSUtil.size(of: folder)
            guard size > 50_000_000 else { continue } // only worth surfacing above ~50MB
            let mtime = FSUtil.lastModified(of: folder)
            items.append(CleanableItem(
                name: name,
                path: folder.path,
                paths: [folder.path],
                sizeBytes: size,
                lastModified: mtime,
                safety: .regenerable,
                category: .appCache,
                explanation: "App cache folder. macOS and the app rebuild caches automatically as needed.",
                action: .trash
            ))
        }
        return items
    }

    /// Known auto-updater leftovers that tend to accumulate silently.
    static func scanUpdaterLeftovers() -> [CleanableItem] {
        let candidates: [(String, String)] = [
            ("Library/Caches/com.google.antigravity.ShipIt", "Antigravity updater leftovers"),
            ("Library/Application Support/Google/GoogleUpdater/crx_cache", "Google Updater component cache"),
        ]
        return candidates.compactMap { (rel, label) in
            let url = home.appendingPathComponent(rel)
            guard FSUtil.exists(url.path) else { return nil }
            let size = FSUtil.size(of: url)
            guard size > 5_000_000 else { return nil }
            return CleanableItem(
                name: label,
                path: url.path,
                paths: [url.path],
                sizeBytes: size,
                lastModified: FSUtil.lastModified(of: url),
                safety: .regenerable,
                category: .appCache,
                explanation: "Leftover from an app auto-updater. Safe to remove; recreated on next update check.",
                action: .trash
            )
        }
    }

    /// Application Support / Caches / Preferences folders whose bundle
    /// identifier doesn't match any currently-installed app.
    static func scanOrphanedSupport(installedBundleIDs: Set<String>) -> [CleanableItem] {
        let dirs = [
            home.appendingPathComponent("Library/Application Support"),
            home.appendingPathComponent("Library/Caches"),
            home.appendingPathComponent("Library/Saved Application State"),
        ]
        var items: [CleanableItem] = []
        for dir in dirs {
            for folder in FSUtil.subdirectories(of: dir.path) {
                let name = folder.lastPathComponent
                // Only treat clearly bundle-id-shaped names (reverse-DNS) as candidates.
                guard name.contains("."), name.split(separator: ".").count >= 3 else { continue }
                let bareID = name.replacingOccurrences(of: ".savedState", with: "")
                // macOS's own services keep data here but aren't apps in /Applications.
                guard !bareID.lowercased().hasPrefix("com.apple.") else { continue }
                guard !installedBundleIDs.contains(bareID) else { continue }
                let size = FSUtil.size(of: folder)
                guard size > 20_000_000 else { continue }
                items.append(CleanableItem(
                    name: name,
                    path: folder.path,
                    paths: [folder.path],
                    sizeBytes: size,
                    lastModified: FSUtil.lastModified(of: folder),
                    safety: .review,
                    category: .orphanedSupport,
                    explanation: "Leftover data for an app that's no longer installed (bundle ID \(bareID) not found).",
                    action: .trash
                ))
            }
        }
        return items
    }
}
