import Foundation

/// Finds stale Xcode/simulator data: superseded iOS Device Support symbol
/// sets, old build folders, SwiftUI preview caches, unused simulator
/// runtimes and shut-down simulator devices.
enum XcodeModule {
    static let devHome = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Developer", isDirectory: true)

    static func scanDeviceSupport() -> [CleanableItem] {
        let dir = devHome.appendingPathComponent("Xcode/iOS DeviceSupport")
        let folders = FSUtil.subdirectories(of: dir.path)
        guard folders.count > 1 else {
            // 0 or 1 folder: nothing "superseded" to flag.
            return []
        }
        // Keep the most recently modified folder (the version Xcode used last);
        // flag the rest as superseded and safe to remove.
        let withDates = folders.map { ($0, FSUtil.lastModified(of: $0) ?? .distantPast) }
        let sorted = withDates.sorted { $0.1 > $1.1 }
        let stale = sorted.dropFirst()

        return stale.map { (url, date) in
            let size = FSUtil.size(of: url)
            return CleanableItem(
                name: url.lastPathComponent,
                path: url.path,
                paths: [url.path],
                sizeBytes: size,
                lastModified: date,
                safety: .regenerable,
                category: .xcodeDeviceSupport,
                explanation: "Superseded debug symbols for a device/OS build. Xcode re-downloads this automatically the next time you debug on that device.",
                action: .trash
            )
        }
    }

    static func scanDerivedData() -> [CleanableItem] {
        let dir = devHome.appendingPathComponent("Xcode/DerivedData")
        let folders = FSUtil.subdirectories(of: dir.path)
        // Never touch the most recently built project automatically -
        // it's likely the one currently open in Xcode.
        let withDates = folders.map { ($0, FSUtil.lastModified(of: $0) ?? .distantPast) }
        let sorted = withDates.sorted { $0.1 > $1.1 }

        return sorted.enumerated().compactMap { (idx, entry) in
            let (url, date) = entry
            let name = url.lastPathComponent
            // Shared indexes/caches (no project name suffix) are always safe.
            let isSharedCache = !name.contains("-") || name.hasSuffix(".noindex")
            let ageDays = FSUtil.daysSince(date)
            guard isSharedCache || idx > 0 else { return nil } // skip most-recent project folder
            guard isSharedCache || ageDays > 7 else { return nil }
            let size = FSUtil.size(of: url)
            guard size > 1_000_000 else { return nil }
            return CleanableItem(
                name: name,
                path: url.path,
                paths: [url.path],
                sizeBytes: size,
                lastModified: date,
                safety: isSharedCache ? .regenerable : .review,
                category: .xcodeDerivedData,
                explanation: isSharedCache
                    ? "Xcode's shared module/symbol cache. Rebuilt automatically on next build."
                    : "Build products for a project not built in the last \(ageDays) days. Xcode rebuilds this the next time you open that project.",
                action: .trash
            )
        }
    }

    static func scanPreviews() -> [CleanableItem] {
        let url = devHome.appendingPathComponent("Xcode/UserData/Previews")
        guard FSUtil.exists(url.path) else { return [] }
        let size = FSUtil.size(of: url)
        guard size > 1_000_000 else { return [] }
        return [CleanableItem(
            name: "SwiftUI Previews Cache",
            path: url.path,
            paths: [url.path],
            sizeBytes: size,
            lastModified: FSUtil.lastModified(of: url),
            safety: .regenerable,
            category: .xcodePreviews,
            explanation: "Cached SwiftUI canvas preview data. Regenerated the next time you open a preview.",
            action: .trash
        )]
    }

    static func scanSimulatorCaches() -> [CleanableItem] {
        var items: [CleanableItem] = []
        let dyld = devHome.appendingPathComponent("CoreSimulator/Caches/dyld")
        if FSUtil.exists(dyld.path) {
            let size = FSUtil.size(of: dyld)
            if size > 1_000_000 {
                items.append(CleanableItem(
                    name: "Simulator dyld cache",
                    path: dyld.path,
                    paths: [dyld.path],
                    sizeBytes: size,
                    lastModified: FSUtil.lastModified(of: dyld),
                    safety: .regenerable,
                    category: .xcodeSimulatorDevice,
                    explanation: "Shared-cache used by the simulator launcher. Rebuilt automatically.",
                    action: .trash
                ))
            }
        }
        return items
    }

    /// Simulator runtimes (iOS/watchOS/tvOS platform images) via `xcrun simctl`.
    /// A runtime is flagged only if there's a newer one installed for the same platform.
    static func scanSimulatorRuntimes() -> [CleanableItem] {
        let (status, output) = FSUtil.run("/usr/bin/xcrun", ["simctl", "runtime", "list", "-j"])
        guard status == 0, let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]]
        else { return [] }

        let byPlatform = Dictionary(grouping: json.values) { ($0["platformIdentifier"] as? String) ?? "" }
        var items: [CleanableItem] = []
        for (_, runtimes) in byPlatform {
            guard runtimes.count > 1 else { continue }
            let sorted = runtimes.sorted { (($0["version"] as? String) ?? "") > (($1["version"] as? String) ?? "") }
            for runtime in sorted.dropFirst() {
                guard let identifier = runtime["identifier"] as? String,
                      let sizeBytes = runtime["sizeBytes"] as? Int64 ?? (runtime["sizeBytes"] as? NSNumber)?.int64Value,
                      let version = runtime["version"] as? String
                else { continue }
                items.append(CleanableItem(
                    name: "iOS Simulator \(version) runtime",
                    path: (runtime["path"] as? String) ?? identifier,
                    paths: [(runtime["path"] as? String) ?? ""],
                    sizeBytes: sizeBytes,
                    lastModified: nil,
                    safety: .review,
                    category: .xcodeSimulatorRuntime,
                    explanation: "A simulator runtime superseded by a newer version. Reinstall anytime from Xcode > Settings > Platforms.",
                    action: .command(["xcrun", "simctl", "runtime", "delete", identifier])
                ))
            }
        }
        return items
    }

    static func scanUnavailableDevices() -> [CleanableItem] {
        let (status, output) = FSUtil.run("/usr/bin/xcrun", ["simctl", "list", "devices", "unavailable", "-j"])
        guard status == 0, let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]]
        else { return [] }

        var items: [CleanableItem] = []
        for (_, deviceList) in devices {
            for device in deviceList {
                guard let udid = device["udid"] as? String,
                      let name = device["name"] as? String else { continue }
                let dataPath = "\(devHome.path)/CoreSimulator/Devices/\(udid)"
                let size = FSUtil.exists(dataPath) ? FSUtil.size(of: URL(fileURLWithPath: dataPath)) : 0
                items.append(CleanableItem(
                    name: "\(name) (unavailable)",
                    path: dataPath,
                    paths: [dataPath],
                    sizeBytes: size,
                    lastModified: nil,
                    safety: .regenerable,
                    category: .xcodeSimulatorDevice,
                    explanation: "Simulator device tied to a runtime that's no longer installed.",
                    action: .command(["xcrun", "simctl", "delete", udid])
                ))
            }
        }
        return items
    }

}
