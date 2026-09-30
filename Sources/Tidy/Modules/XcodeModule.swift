import Foundation

/// Finds Xcode and simulator data: device support symbols, build data,
/// archives, documentation caches, simulator runtimes, devices and their
/// dyld shared caches.
///
/// Safety rules used here:
/// - `.regenerable` only for data Xcode or the simulator rebuilds by itself
///   with no user-visible loss, and that can be removed without an admin
///   prompt (scheduled auto-clean runs every `.regenerable` item unattended).
/// - `.review` for anything that costs a re-download, wipes simulator app
///   data, needs an admin password, or is a build the user may still need.
enum XcodeModule {
    static let devHome = FSUtil.home.appendingPathComponent("Library/Developer", isDirectory: true)
    static let systemDyldCacheRoot = URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Caches/dyld", isDirectory: true)

    static let staleDeviceDays = 30
    static let staleRuntimeDays = 60
    static let staleBuildDataDays = 30

    // MARK: - Device Support

    static let deviceSupportPlatforms = ["iOS", "watchOS", "tvOS", "visionOS", "xrOS", "macOS"]

    static func scanDeviceSupport() -> [CleanableItem] {
        var items: [CleanableItem] = []
        for platform in deviceSupportPlatforms {
            let dir = devHome.appendingPathComponent("Xcode/\(platform) DeviceSupport")
            let sorted = FSUtil.subdirectories(of: dir.path)
                .map { ($0, FSUtil.lastModified(of: $0) ?? .distantPast) }
                .sorted { $0.1 > $1.1 }
            guard let latest = sorted.first else { continue }

            for (url, date) in sorted.dropFirst() {
                let size = FSUtil.size(of: url)
                guard size > 1_000_000 else { continue }
                items.append(CleanableItem(
                    name: "\(platform) \(url.lastPathComponent)",
                    path: url.path,
                    paths: [url.path],
                    sizeBytes: size,
                    lastModified: date,
                    safety: .regenerable,
                    category: .xcodeDeviceSupport,
                    explanation: "Superseded debug symbols for an older \(platform) version. Xcode re-copies them automatically if you debug on a device running that version again.",
                    action: .trash
                ))
            }

            // The newest set belongs to the device you connected last, so it's
            // only offered (never auto-cleaned) once it has gone unused a while.
            let (url, date) = latest
            let age = FSUtil.daysSince(date)
            let size = FSUtil.size(of: url)
            if age >= staleDeviceDays, size > 1_000_000 {
                items.append(CleanableItem(
                    name: "\(platform) \(url.lastPathComponent)",
                    path: url.path,
                    paths: [url.path],
                    sizeBytes: size,
                    lastModified: date,
                    safety: .review,
                    category: .xcodeDeviceSupport,
                    explanation: "Debug symbols for the last \(platform) device you connected, untouched for \(age) days. Xcode re-copies them (a few minutes) the next time that device connects.",
                    action: .trash
                ))
            }
        }
        return items
    }

    // MARK: - Build data, archives, documentation

    static func scanDerivedData() -> [CleanableItem] {
        let dir = devHome.appendingPathComponent("Xcode/DerivedData")
        return FSUtil.subdirectories(of: dir.path).compactMap { url in
            let name = url.lastPathComponent
            let date = FSUtil.lastModified(of: url)
            let age = FSUtil.daysSince(date)
            let size = FSUtil.size(of: url)
            guard size > 1_000_000 else { return nil }

            // Shared caches (ModuleCache.noindex, SymbolCache.noindex, …) have
            // no "-<hash>" project suffix.
            let isSharedCache = !name.contains("-") || name.hasSuffix(".noindex")
            let projectName = name.components(separatedBy: "-").dropLast().joined(separator: "-")

            if isSharedCache {
                return CleanableItem(
                    name: name, path: url.path, paths: [url.path],
                    sizeBytes: size, lastModified: date,
                    safety: .regenerable, category: .xcodeDerivedData,
                    explanation: "Xcode's shared module/symbol cache. Rebuilt automatically on your next build.",
                    action: .trash
                )
            }
            let stale = age >= staleBuildDataDays
            return CleanableItem(
                name: projectName.isEmpty ? name : "\(projectName) build data",
                path: url.path, paths: [url.path],
                sizeBytes: size, lastModified: date,
                safety: stale ? .regenerable : .review,
                category: .xcodeDerivedData,
                explanation: stale
                    ? "Build products and index for a project not built in \(age) days. Xcode rebuilds it the next time you open the project."
                    : "Build products and index for a project built \(age == 0 ? "today" : "\(age) days ago") — likely still in use. Removing it only means a full rebuild; quit Xcode first.",
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

    static func scanDocumentation() -> [CleanableItem] {
        ["DocumentationCache", "DocumentationIndex"].compactMap { folder in
            let url = devHome.appendingPathComponent("Xcode/\(folder)")
            guard FSUtil.exists(url.path) else { return nil }
            let size = FSUtil.size(of: url)
            guard size > 1_000_000 else { return nil }
            return CleanableItem(
                name: folder == "DocumentationCache" ? "Xcode documentation cache" : "Xcode documentation index",
                path: url.path,
                paths: [url.path],
                sizeBytes: size,
                lastModified: FSUtil.lastModified(of: url),
                safety: .regenerable,
                category: .xcodeDocumentation,
                explanation: "Downloaded developer documentation. Xcode fetches pages again on demand when you open them.",
                action: .trash
            )
        }
    }

    /// Archives are builds the user made (often ones they shipped), so they
    /// are only ever offered for review — never auto-cleaned.
    static func scanArchives() -> [CleanableItem] {
        let root = devHome.appendingPathComponent("Xcode/Archives")
        var items: [CleanableItem] = []
        for dayFolder in FSUtil.subdirectories(of: root.path) {
            for archive in FSUtil.subdirectories(of: dayFolder.path) where archive.pathExtension == "xcarchive" {
                let size = FSUtil.size(of: archive)
                guard size > 1_000_000 else { continue }
                let date = FSUtil.lastModified(of: archive)
                items.append(CleanableItem(
                    name: archive.deletingPathExtension().lastPathComponent,
                    path: archive.path,
                    paths: [archive.path],
                    sizeBytes: size,
                    lastModified: date,
                    safety: .review,
                    category: .xcodeArchive,
                    explanation: "An archived build from \(FSUtil.daysSince(date)) days ago. Keep it if you may need to symbolicate crash reports from this build or re-export it.",
                    action: .trash
                ))
            }
        }
        return items
    }

    // MARK: - Simulator caches

    /// Pre-Xcode 15 location of the simulator dyld cache, in the user's Library.
    static func scanSimulatorCaches() -> [CleanableItem] {
        let dyld = devHome.appendingPathComponent("CoreSimulator/Caches/dyld")
        guard FSUtil.exists(dyld.path) else { return [] }
        let size = FSUtil.size(of: dyld)
        guard size > 1_000_000 else { return [] }
        return [CleanableItem(
            name: "Simulator dyld cache (legacy location)",
            path: dyld.path,
            paths: [dyld.path],
            sizeBytes: size,
            lastModified: FSUtil.lastModified(of: dyld),
            safety: .regenerable,
            category: .xcodeSimulatorCache,
            explanation: "Shared-library cache used by older simulators. Rebuilt automatically.",
            action: .trash
        )]
    }

    /// Xcode 15+ keeps simulator dyld caches system-wide, keyed by host macOS
    /// build and then runtime: /Library/Developer/CoreSimulator/Caches/dyld/<host build>/<runtime id>.
    /// These are root-owned: in-use ones are removed through simctl, and stale
    /// ones can only be removed by the user in Finder (a sandboxed app can't
    /// ask for admin rights), so none of them are `.regenerable`.
    static func scanSystemDyldCaches() -> [CleanableItem] {
        let hostBuild = hostOSBuild()
        let simctl = FSUtil.simctlPath
        let installedCaches = installedRuntimeCacheNames()
        var items: [CleanableItem] = []

        for buildDir in FSUtil.subdirectories(of: systemDyldCacheRoot.path) {
            if buildDir.lastPathComponent != hostBuild {
                let size = FSUtil.size(of: buildDir)
                guard size > 1_000_000 else { continue }
                items.append(CleanableItem(
                    name: "Simulator dyld cache for macOS build \(buildDir.lastPathComponent)",
                    path: buildDir.path,
                    paths: [buildDir.path],
                    sizeBytes: size,
                    lastModified: FSUtil.lastModified(of: buildDir),
                    safety: .personal,
                    category: .xcodeSimulatorCache,
                    explanation: "Built for an older macOS version (you're on \(hostBuild)), so nothing uses it anymore. It's owned by macOS, so drag it to the Trash in Finder yourself — Finder will ask for your password.",
                    action: .reveal(buildDir.path)
                ))
                continue
            }

            // Without simctl there's no way to tell which caches are still in
            // use, so don't guess — every one would look orphaned.
            guard !installedCaches.isEmpty else { continue }

            // Each folder is "<runtime identifier>.<runtime build>", e.g.
            // "com.apple.CoreSimulator.SimRuntime.iOS-26-2.23C54".
            for runtimeDir in FSUtil.subdirectories(of: buildDir.path) where runtimeDir.lastPathComponent.hasPrefix("com.apple.CoreSimulator.SimRuntime.") {
                let folderName = runtimeDir.lastPathComponent
                let size = FSUtil.size(of: runtimeDir)
                guard size > 1_000_000 else { continue }
                let label = runtimeLabel(fromIdentifier: (folderName as NSString).deletingPathExtension)

                if let runtimeID = installedCaches[folderName] {
                    guard let simctl else { continue }
                    items.append(CleanableItem(
                        name: "\(label) simulator dyld cache",
                        path: runtimeDir.path,
                        paths: [runtimeDir.path],
                        sizeBytes: size,
                        lastModified: FSUtil.lastModified(of: runtimeDir),
                        safety: .review,
                        category: .xcodeSimulatorCache,
                        explanation: "Speeds up \(label) simulator launches. macOS rebuilds it automatically (a few minutes) the next time one boots — worth removing only if you rarely use this runtime.",
                        action: .command([simctl, "runtime", "dyld_shared_cache", "remove", runtimeID])
                    ))
                } else {
                    items.append(CleanableItem(
                        name: "\(label) simulator dyld cache (runtime removed)",
                        path: runtimeDir.path,
                        paths: [runtimeDir.path],
                        sizeBytes: size,
                        lastModified: FSUtil.lastModified(of: runtimeDir),
                        safety: .personal,
                        category: .xcodeSimulatorCache,
                        explanation: "Left behind by a simulator runtime that's no longer installed, so nothing uses it. It's owned by macOS, so drag it to the Trash in Finder yourself — Finder will ask for your password.",
                        action: .reveal(runtimeDir.path)
                    ))
                }
            }
        }
        return items
    }

    // MARK: - Simulator runtimes

    /// Runtimes are large and re-downloadable, but removing one breaks every
    /// simulator on it until it's reinstalled, so they're always `.review`.
    static func scanSimulatorRuntimes() -> [CleanableItem] {
        guard let simctl = FSUtil.simctlPath,
              let json = FSUtil.simctlJSON(["runtime", "list", "-j"]) as? [String: [String: Any]]
        else { return [] }

        let runtimes = Array(json.values)
        let newestByPlatform = Dictionary(grouping: runtimes) { ($0["platformIdentifier"] as? String) ?? "" }
            .mapValues { group in
                group.compactMap { $0["version"] as? String }
                    .max { $0.compare($1, options: .numeric) == .orderedAscending }
            }

        var items: [CleanableItem] = []
        for runtime in runtimes {
            guard (runtime["deletable"] as? Bool) != false,
                  let identifier = runtime["identifier"] as? String,
                  let sizeBytes = (runtime["sizeBytes"] as? NSNumber)?.int64Value,
                  let version = runtime["version"] as? String
            else { continue }

            let platform = (runtime["platformIdentifier"] as? String) ?? ""
            let runtimeID = (runtime["runtimeIdentifier"] as? String) ?? ""
            let label = runtimeLabel(fromIdentifier: runtimeID, fallbackVersion: version)
            let lastUsed = (runtime["lastUsedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }
            let isSuperseded = newestByPlatform[platform].flatMap { $0 }.map {
                version.compare($0, options: .numeric) == .orderedAscending
            } ?? false

            let reason: String
            if isSuperseded {
                reason = "A newer \(label.components(separatedBy: " ").first ?? "") runtime is installed."
            } else if let lastUsed {
                let age = FSUtil.daysSince(lastUsed)
                guard age >= staleRuntimeDays else { continue }
                reason = "Not used in \(age) days."
            } else {
                reason = "Never used by any simulator on this Mac."
            }

            items.append(CleanableItem(
                name: "\(label) simulator runtime",
                path: (runtime["path"] as? String) ?? identifier,
                paths: [],
                sizeBytes: sizeBytes,
                lastModified: lastUsed,
                safety: .review,
                category: .xcodeSimulatorRuntime,
                explanation: "\(reason) Simulators on it stop working until you reinstall it from Xcode › Settings › Components.",
                action: .command([simctl, "runtime", "delete", identifier])
            ))
        }
        return items
    }

    // MARK: - Simulator devices

    static func scanUnavailableDevices() -> [CleanableItem] {
        guard let simctl = FSUtil.simctlPath else { return [] }
        return simulatorDevices().compactMap { device in
            guard device.isAvailable == false else { return nil }
            return CleanableItem(
                name: "\(device.name) (unavailable)",
                path: device.path,
                paths: [device.path],
                sizeBytes: FSUtil.exists(device.path) ? FSUtil.size(of: URL(fileURLWithPath: device.path)) : 0,
                lastModified: device.lastBooted,
                safety: .regenerable,
                category: .xcodeSimulatorDevice,
                explanation: "Simulator device tied to a runtime that's no longer installed, so it can't boot anymore.",
                action: .command([simctl, "delete", device.udid])
            )
        }
    }

    /// Working simulators that haven't been booted in a while. Erasing (not
    /// deleting) wipes the apps and data inside but keeps the simulator in
    /// Xcode's device list, so nothing needs to be recreated.
    static func scanStaleDevices() -> [CleanableItem] {
        guard let simctl = FSUtil.simctlPath else { return [] }
        return simulatorDevices().compactMap { device in
            guard device.isAvailable, device.state == "Shutdown", FSUtil.exists(device.path) else { return nil }
            let age = device.lastBooted.map { FSUtil.daysSince($0) }
            if let age, age < staleDeviceDays { return nil }
            let size = FSUtil.size(of: URL(fileURLWithPath: device.path))
            guard size > 50_000_000 else { return nil }
            return CleanableItem(
                name: "\(device.name) · \(device.runtimeLabel)",
                path: device.path,
                paths: [device.path],
                sizeBytes: size,
                lastModified: device.lastBooted,
                safety: .review,
                category: .xcodeSimulatorDevice,
                explanation: "\(age.map { "Not booted in \($0) days." } ?? "Never booted, but holding data.") Erasing wipes the apps and data installed in it; the simulator itself stays in Xcode's list.",
                action: .command([simctl, "erase", device.udid])
            )
        }
    }

    // MARK: - Helpers

    struct SimDevice {
        let udid: String
        let name: String
        let state: String
        let isAvailable: Bool
        let lastBooted: Date?
        let runtimeLabel: String
        let path: String
    }

    static func simulatorDevices() -> [SimDevice] {
        guard let json = FSUtil.simctlJSON(["list", "devices", "-j"]) as? [String: Any],
              let byRuntime = json["devices"] as? [String: [[String: Any]]]
        else { return [] }

        let iso = ISO8601DateFormatter()
        return byRuntime.flatMap { runtimeID, devices in
            devices.compactMap { device -> SimDevice? in
                guard let udid = device["udid"] as? String, let name = device["name"] as? String else { return nil }
                return SimDevice(
                    udid: udid,
                    name: name,
                    state: (device["state"] as? String) ?? "",
                    isAvailable: (device["isAvailable"] as? Bool) ?? true,
                    lastBooted: (device["lastBootedAt"] as? String).flatMap { iso.date(from: $0) },
                    runtimeLabel: runtimeLabel(fromIdentifier: runtimeID),
                    path: devHome.appendingPathComponent("CoreSimulator/Devices/\(udid)").path
                )
            }
        }
    }

    /// Maps each usable runtime's dyld cache folder name ("<identifier>.<build>")
    /// to its identifier. Includes runtimes bundled inside Xcode, not just
    /// downloaded disk images. Matching on build means a cache left over from
    /// an older build of the same OS version is correctly seen as orphaned.
    static func installedRuntimeCacheNames() -> [String: String] {
        guard let json = FSUtil.simctlJSON(["list", "runtimes", "-j"]) as? [String: Any],
              let runtimes = json["runtimes"] as? [[String: Any]]
        else { return [:] }
        var names: [String: String] = [:]
        for runtime in runtimes where (runtime["isAvailable"] as? Bool) != false {
            guard let identifier = runtime["identifier"] as? String,
                  let build = runtime["buildversion"] as? String else { continue }
            names["\(identifier).\(build)"] = identifier
        }
        return names
    }

    /// "com.apple.CoreSimulator.SimRuntime.watchOS-26-2" → "watchOS 26.2".
    static func runtimeLabel(fromIdentifier identifier: String, fallbackVersion: String? = nil) -> String {
        guard let suffix = identifier.components(separatedBy: ".").last, !suffix.isEmpty else {
            return fallbackVersion.map { "Simulator \($0)" } ?? "Simulator"
        }
        var parts = suffix.components(separatedBy: "-")
        let platform = parts.removeFirst()
        return parts.isEmpty ? platform : "\(platform) \(parts.joined(separator: "."))"
    }

    static func hostOSBuild() -> String {
        var size = 0
        sysctlbyname("kern.osversion", nil, &size, nil, 0)
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("kern.osversion", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}
