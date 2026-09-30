import Foundation
import CoreServices

/// Surfaces installed apps that haven't been opened in a long time, sized
/// so the user can prioritize. Never lists Apple system apps — those are
/// integral to macOS and mostly tiny anyway.
enum UnusedAppsModule {
    static let home = FSUtil.home
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

                items.append(CleanableItem(
                    name: appName.replacingOccurrences(of: ".app", with: ""),
                    path: path,
                    paths: [path],
                    sizeBytes: size,
                    lastModified: lastUsed,
                    safety: .review,
                    category: .unusedApp,
                    explanation: (lastUsed == nil
                        ? "No recorded launch date; installed but possibly never opened."
                        : "Not opened in \(ageDays) days.")
                        + " Drag it to the Trash in Finder if you don't need it.",
                    action: .reveal(path)
                ))
            }
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Spotlight's kMDItemLastUsedDate (set by LaunchServices on launch)
    /// rather than the file's raw access time, which Finder/Spotlight/a scan
    /// can bump without the app ever having been opened.
    private static func lastUsedDate(path: String) -> Date? {
        guard let item = MDItemCreate(nil, path as CFString) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }
}
