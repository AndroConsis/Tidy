import Foundation
import AppKit

/// Removes an app together with the files it left in the user's Library.
/// Leftovers are matched only by the app's exact bundle identifier or exact
/// name, never by a partial match, so a vendor's shared folders (and other
/// apps' data) are never swept up. Apple's apps, Tidy itself and running
/// apps are never offered.
enum UninstallerModule {
    struct InstalledApp: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let name: String
        /// CFBundleName, which apps usually name their support folders after.
        let bundleName: String?
        let bundleID: String
        let version: String?
        let lastOpened: Date?
        /// Installed by the App Store: owned by the system, so macOS may ask
        /// the user to remove it from Finder or Launchpad instead.
        let isFromAppStore: Bool
        var sizeBytes: Int64 = 0
    }

    struct Leftover: Identifiable, Hashable {
        var id: URL { url }
        let url: URL
        let kind: String
        let sizeBytes: Int64
    }

    static func installedApps(home: URL = FSUtil.home) -> [InstalledApp] {
        let ownID = Bundle.main.bundleIdentifier ?? "com.prateek.tidy"
        var apps: [InstalledApp] = []
        for base in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            for url in appBundles(in: base) {
                guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier,
                      !id.hasPrefix("com.apple."), id != ownID else { continue }
                let info = bundle.infoDictionary ?? [:]
                apps.append(InstalledApp(
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    bundleName: info["CFBundleName"] as? String,
                    bundleID: id,
                    version: info["CFBundleShortVersionString"] as? String,
                    lastOpened: lastOpened(url),
                    isFromAppStore: FSUtil.exists(url.appendingPathComponent("Contents/_MASReceipt").path)
                ))
            }
        }
        return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Apps directly in the folder, plus apps one folder down (some
    /// installers put an app inside a folder of its own).
    private static func appBundles(in base: URL) -> [URL] {
        let entries = (try? FSUtil.fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var result: [URL] = []
        for entry in entries {
            if entry.pathExtension == "app" {
                result.append(entry)
            } else if (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true, entry.lastPathComponent != "Utilities" {
                let inner = (try? FSUtil.fm.contentsOfDirectory(at: entry, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
                result += inner.filter { $0.pathExtension == "app" }
            }
        }
        return result
    }

    static func lastOpened(_ url: URL) -> Date? {
        guard let item = MDItemCreate(nil, url.path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    static func isRunning(_ app: InstalledApp) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
    }

    static func leftovers(for app: InstalledApp, home: URL = FSUtil.home) -> [Leftover] {
        let library = home.appendingPathComponent("Library")
        let id = app.bundleID
        // Very short names could collide with another app's folder.
        let names = Set([app.name, app.bundleName].compactMap { $0 }.filter { $0.count >= 4 })

        var candidates: [(String, String)] = [
            ("Application Support/\(id)", "App data"),
            ("Caches/\(id)", "Cache"),
            ("Preferences/\(id).plist", "Settings"),
            ("Saved Application State/\(id).savedState", "Saved windows"),
            ("Logs/\(id)", "Logs"),
            ("HTTPStorages/\(id)", "Web data"),
            ("HTTPStorages/\(id).binarycookies", "Cookies"),
            ("Cookies/\(id).binarycookies", "Cookies"),
            ("WebKit/\(id)", "Web data"),
        ]
        for name in names {
            candidates += [
                ("Application Support/\(name)", "App data"),
                ("Caches/\(name)", "Cache"),
                ("Logs/\(name)", "Logs"),
            ]
        }

        var found: [Leftover] = []
        var seen = Set<String>()
        for (relative, kind) in candidates {
            let url = library.appendingPathComponent(relative)
            guard FSUtil.exists(url.path), seen.insert(url.standardizedFileURL.path).inserted else { continue }
            found.append(Leftover(url: url, kind: kind, sizeBytes: FSUtil.size(of: url)))
        }
        // Per-machine settings and login helpers carry the bundle ID as a prefix.
        for (folder, kind) in [("Preferences/ByHost", "Settings"), ("LaunchAgents", "Login helper")] {
            let dir = library.appendingPathComponent(folder)
            let files = (try? FSUtil.fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for url in files where url.lastPathComponent.hasPrefix(id + ".") && url.pathExtension == "plist" {
                found.append(Leftover(url: url, kind: kind, sizeBytes: FSUtil.size(of: url)))
            }
        }
        return found.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
