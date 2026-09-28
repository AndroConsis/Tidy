import Foundation

/// Items Tidy never deletes itself — it only detects them and tells the
/// user the supported, correct way to reclaim the space (a Settings
/// toggle, emptying Trash, etc.). This is where Photos/iCloud guidance lives.
enum SystemModule {
    static let home = FileManager.default.homeDirectoryForCurrentUser

    static func scan(hasFullDiskAccess: Bool) -> [CleanableItem] {
        var items: [CleanableItem] = []

        // Photos library: guide only. Deleting photos locally while iCloud
        // Photos sync is on deletes them from iCloud too, so Tidy never
        // touches this — it only detects size and points at the safe fix.
        let photosPath = home.appendingPathComponent("Pictures/Photos Library.photoslibrary").path
        if FSUtil.exists(photosPath) {
            let size = hasFullDiskAccess ? FSUtil.size(of: URL(fileURLWithPath: photosPath)) : 0
            items.append(CleanableItem(
                name: "Photos Library",
                path: photosPath,
                paths: [],
                sizeBytes: size,
                lastModified: nil,
                safety: .personal,
                category: .system,
                explanation: "If iCloud Photos is on, turn on \"Optimize Mac Storage\" in Photos > Settings > iCloud instead of deleting anything. Full-size originals stay in iCloud and download on demand.",
                action: .guide("x-apple.systempreferences:com.apple.Photos-Settings.extension")
            ))
        }

        // Trash: can't be sized without Full Disk Access; guide the user to grant it,
        // and to simply empty the Trash for anything Tidy has already moved there.
        if !hasFullDiskAccess {
            items.append(CleanableItem(
                name: "Full Disk Access not granted",
                path: "",
                paths: [],
                sizeBytes: 0,
                lastModified: nil,
                safety: .personal,
                category: .system,
                explanation: "Tidy can't see the size of Trash, Mail, Messages or Safari data without Full Disk Access. Grant it in System Settings > Privacy & Security > Full Disk Access.",
                action: .guide("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
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
