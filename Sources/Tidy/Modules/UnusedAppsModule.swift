import Foundation
import AppKit

/// Surfaces installed apps that haven't been opened in a long time, sized
/// so the user can prioritize. Never lists Apple system apps — those are
/// integral to macOS and mostly tiny anyway.
enum UnusedAppsModule {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let staleDays = 90

    static func scan() -> [CleanableItem] {
        var items: [CleanableItem] = []
        for base in ["/Applications", home.appendingPathComponent("Applications").path] {
            guard let appNames = try? FileManager.default.contentsOfDirectory(atPath: base) else { continue }
            for appName in appNames where appName.hasSuffix(".app") {
                let path = "\(base)/\(appName)"
                guard let bundle = Bundle(path: path) else { continue }
                let bid = bundle.bundleIdentifier ?? ""
                guard !bid.hasPrefix("com.apple.") else { continue }

                let lastUsed = lastUsedDate(path: path)
                let ageDays = FSUtil.daysSince(lastUsed)
                guard ageDays >= staleDays else { continue }

                let size = FSUtil.size(of: URL(fileURLWithPath: path))
                guard size > 10_000_000 else { continue }

                let dataPaths = relatedDataPaths(bundleID: bid)
                items.append(CleanableItem(
                    name: appName.replacingOccurrences(of: ".app", with: ""),
                    path: path,
                    paths: [path] + dataPaths,
                    sizeBytes: size + dataPaths.reduce(0) { $0 + FSUtil.size(of: URL(fileURLWithPath: $1)) },
                    lastModified: lastUsed,
                    safety: .review,
                    category: .unusedApp,
                    explanation: lastUsed == nil
                        ? "No recorded launch date found; installed but possibly never opened."
                        : "Not opened in \(ageDays) days.",
                    action: .trash
                ))
            }
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static let mdlsFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss Z"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Uses Spotlight's kMDItemLastUsedDate (set by LaunchServices on launch)
    /// rather than the file's raw access time, which Finder/Spotlight/a scan
    /// can bump without the app ever having been opened.
    private static func lastUsedDate(path: String) -> Date? {
        let (status, output) = FSUtil.run("/usr/bin/mdls", ["-raw", "-name", "kMDItemLastUsedDate", path])
        guard status == 0 else { return nil }
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != "(null)", !trimmed.isEmpty else { return nil }
        return mdlsFormatter.date(from: trimmed)
    }

    /// Best-effort collection of an app's leftover support files, matched by bundle ID.
    private static func relatedDataPaths(bundleID: String) -> [String] {
        guard !bundleID.isEmpty else { return [] }
        let candidates = [
            home.appendingPathComponent("Library/Application Support/\(bundleID)").path,
            home.appendingPathComponent("Library/Caches/\(bundleID)").path,
            home.appendingPathComponent("Library/Preferences/\(bundleID).plist").path,
            home.appendingPathComponent("Library/Containers/\(bundleID)").path,
            home.appendingPathComponent("Library/Saved Application State/\(bundleID).savedState").path,
        ]
        return candidates.filter { FSUtil.exists($0) }
    }
}
