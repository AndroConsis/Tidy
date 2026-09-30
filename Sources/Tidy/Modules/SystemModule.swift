import Foundation

/// Items Tidy never deletes itself — it only detects them and tells the
/// user the supported, correct way to reclaim the space (a Settings
/// toggle, emptying Trash, etc.). This is where Photos/iCloud guidance lives.
enum SystemModule {
    static let home = FSUtil.home

    static func scan() -> [CleanableItem] {
        var items: [CleanableItem] = []

        // Photos library: guide only. Deleting photos locally while iCloud
        // Photos sync is on deletes them from iCloud too, so Tidy never
        // touches this — it only points at the safe fix. The library is
        // privacy-protected, so the sandbox can't size it.
        let photosPath = home.appendingPathComponent("Pictures/Photos Library.photoslibrary").path
        if FSUtil.exists(photosPath) {
            items.append(CleanableItem(
                name: "Photos Library",
                path: photosPath,
                paths: [],
                sizeBytes: 0,
                lastModified: nil,
                safety: .personal,
                category: .system,
                explanation: "If iCloud Photos is on, turn on \"Optimize Mac Storage\" in Photos > Settings > iCloud instead of deleting anything. Full-size originals stay in iCloud and download on demand.",
                action: .guide("x-apple.systempreferences:com.apple.Photos-Settings.extension")
            ))
        }

        // Local Time Machine snapshots can quietly hold old versions of changed/deleted files.
        let (status, output) = FSUtil.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        if status == 0 {
            let snapshots = output.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }
            if !snapshots.isEmpty {
                items.append(CleanableItem(
                    name: "\(snapshots.count) local Time Machine snapshot(s)",
                    path: "",
                    paths: [],
                    sizeBytes: 0,
                    lastModified: nil,
                    safety: .personal,
                    category: .system,
                    explanation: "macOS manages these automatically and purges them under disk pressure. Run 'tmutil thinlocalsnapshots / <bytes> 4' yourself if you need space immediately; Tidy won't do this automatically since it can remove your only local restore point.",
                    action: .guide("")
                ))
            }
        }

        return items
    }
}
