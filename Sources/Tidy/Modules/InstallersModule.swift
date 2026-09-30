import Foundation

/// Finds downloaded installers (.dmg/.pkg/.zip/.xip) in Downloads that are
/// for apps already installed, or are just old, so they can be cleared out.
/// This is the "you installed Chrome, the .dmg is still sitting in
/// Downloads" case.
///
/// Only Downloads is scanned: the sandbox grants it via entitlement with no
/// prompt, whereas Desktop would trigger a separate privacy prompt.
enum InstallersModule {
    static let home = FSUtil.home
    static let applicationFolders = ["/Applications", FSUtil.home.appendingPathComponent("Applications").path]

    static func installedBundleIDs() -> Set<String> {
        Set(installedApps().compactMap { Bundle(path: $0)?.bundleIdentifier })
    }

    static func installedApps() -> [String] {
        applicationFolders.flatMap { base -> [String] in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: base)) ?? []
            return names.filter { $0.hasSuffix(".app") }.map { "\(base)/\($0)" }
        }
    }

    /// "Google Chrome.app" / "googlechrome.dmg" / "GoogleChrome-124.0.dmg" → "googlechrome".
    static func normalized(_ name: String) -> String {
        let base = (name as NSString).deletingPathExtension.lowercased()
        return String(base.unicodeScalars.filter { CharacterSet.lowercaseLetters.contains($0) })
    }

    /// Installer mounting (hdiutil) isn't allowed in the sandbox, so match the
    /// installer's file name against installed app names instead. Requires a
    /// reasonably long name so "VS.dmg" doesn't match every app starting with "vs".
    static func matchingInstalledApp(for installer: URL, appNames: [(display: String, key: String)]) -> String? {
        let key = normalized(installer.lastPathComponent)
        return appNames
            .filter { $0.key.count >= 4 && key.hasPrefix($0.key) }
            .max { $0.key.count < $1.key.count }?
            .display
    }

    static func scan() -> [CleanableItem] {
        let appNames = installedApps().map { path -> (display: String, key: String) in
            let display = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            return (display, normalized(display))
        }
        let dir = home.appendingPathComponent("Downloads")
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        var items: [CleanableItem] = []
        for file in files {
            let ext = file.pathExtension.lowercased()
            guard ["dmg", "pkg", "zip", "xip"].contains(ext) else { continue }
            let size = FSUtil.size(of: file)
            guard size > 5_000_000 else { continue }
            let mtime = FSUtil.lastModified(of: file)
            let ageDays = FSUtil.daysSince(mtime)

            let explanation: String
            if ext != "zip", let app = matchingInstalledApp(for: file, appNames: appNames), ageDays >= 1 {
                explanation = "Looks like the installer for \(app), which is already installed. The installer itself isn't needed anymore."
            } else if ageDays > 30 {
                explanation = "Downloaded installer, untouched for \(ageDays) days."
            } else {
                continue
            }
            items.append(CleanableItem(
                name: file.lastPathComponent,
                path: file.path,
                paths: [file.path],
                sizeBytes: size,
                lastModified: mtime,
                safety: .review,
                category: .installer,
                explanation: explanation,
                action: .trash
            ))
        }
        return items
    }
}
