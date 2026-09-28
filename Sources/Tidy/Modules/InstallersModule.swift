import Foundation
import AppKit

/// Finds downloaded installers (.dmg/.pkg/.zip/.xip) in Downloads/Desktop
/// that are for apps already installed, or are just old, so they can be
/// cleared out. This is the "you installed Chrome, the .dmg is still
/// sitting in Downloads" case.
enum InstallersModule {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let watchedFolders = ["Downloads", "Desktop"]

    static func installedBundleIDs() -> Set<String> {
        var ids = Set<String>()
        for base in ["/Applications", home.appendingPathComponent("Applications").path] {
            guard let apps = try? FileManager.default.contentsOfDirectory(atPath: base) else { continue }
            for appName in apps where appName.hasSuffix(".app") {
                let bundlePath = "\(base)/\(appName)"
                if let bundle = Bundle(path: bundlePath), let id = bundle.bundleIdentifier {
                    ids.insert(id)
                }
            }
        }
        return ids
    }

    /// Inspects a .dmg by mounting it read-only, reading the bundled app's
    /// Info.plist, then detaching. Returns the bundle identifier if found.
    static func bundleID(inDMG path: String) -> String? {
        let (status, output) = FSUtil.run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-noverify", "-plist", path])
        guard status == 0, let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]]
        else { return nil }

        var mountPoint: String?
        for entity in entities {
            if let mp = entity["mount-point"] as? String {
                mountPoint = mp
                break
            }
        }
        defer {
            if let mp = mountPoint {
                _ = FSUtil.run("/usr/bin/hdiutil", ["detach", mp, "-quiet"])
            }
        }
        guard let mp = mountPoint,
              let contents = try? FileManager.default.contentsOfDirectory(atPath: mp)
        else { return nil }

        for item in contents where item.hasSuffix(".app") {
            if let bundle = Bundle(path: "\(mp)/\(item)") {
                return bundle.bundleIdentifier
            }
        }
        return nil
    }

    static func bundleID(inPKGReceiptsFor path: String) -> String? {
        // .pkg files don't mount; match against pkgutil receipts by filename heuristic
        // is unreliable, so pkgs are flagged purely by age instead (see scan()).
        nil
    }

    static func scan() -> [CleanableItem] {
        let installed = installedBundleIDs()
        var items: [CleanableItem] = []

        for folderName in watchedFolders {
            let dir = home.appendingPathComponent(folderName)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]
            ) else { continue }

            for file in files {
                let ext = file.pathExtension.lowercased()
                guard ["dmg", "pkg", "zip", "xip"].contains(ext) else { continue }
                let size = FSUtil.size(of: file)
                guard size > 5_000_000 else { continue }
                let mtime = FSUtil.lastModified(of: file)
                let ageDays = FSUtil.daysSince(mtime)

                if ext == "dmg", let bid = bundleID(inDMG: file.path), installed.contains(bid) {
                    items.append(CleanableItem(
                        name: file.lastPathComponent,
                        path: file.path,
                        paths: [file.path],
                        sizeBytes: size,
                        lastModified: mtime,
                        safety: .review,
                        category: .installer,
                        explanation: "The app inside this installer (\(bid)) is already installed. The installer itself isn't needed anymore.",
                        action: .trash
                    ))
                } else if ageDays > 30 {
                    items.append(CleanableItem(
                        name: file.lastPathComponent,
                        path: file.path,
                        paths: [file.path],
                        sizeBytes: size,
                        lastModified: mtime,
                        safety: .review,
                        category: .installer,
                        explanation: "Downloaded installer, untouched for \(ageDays) days.",
                        action: .trash
                    ))
                }
            }
        }
        return items
    }
}
