import Foundation
import AppKit

/// Android Studio, the Android SDK and its emulators. Emulators and system
/// images take many gigabytes each, but they're things the user set up, so
/// they're `.review`: Tidy lists them and waits. Only download and IDE caches
/// that Android Studio rebuilds by itself are `.regenerable`.
enum AndroidModule {
    static let studioBundleID = "com.google.android.studio"

    static func avdRoot(home: URL = FSUtil.home) -> URL {
        home.appendingPathComponent(".android/avd")
    }

    /// The SDK lives here unless the user moved it in Android Studio.
    static func sdkRoot(home: URL = FSUtil.home) -> URL {
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let path = ProcessInfo.processInfo.environment[key], FSUtil.exists(path) {
                return URL(fileURLWithPath: path)
            }
        }
        return home.appendingPathComponent("Library/Android/sdk")
    }

    struct VirtualDevice {
        let name: String
        let dir: URL
        let ini: URL?
        let systemImage: String?   // e.g. "system-images/android-34/google_apis/arm64-v8a"
        let lastUsed: Date?
        let looksRunning: Bool
    }

    /// Reads `key=value` files such as an AVD's config.ini.
    static func readINI(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
        }
        return values
    }

    static func normalizeImagePath(_ path: String) -> String {
        path.split(separator: "/").joined(separator: "/")
    }

    static func virtualDevices(home: URL = FSUtil.home) -> [VirtualDevice] {
        let root = avdRoot(home: home)
        let fm = FSUtil.fm
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return entries.filter { $0.pathExtension == "avd" }.map { dir in
            let id = dir.deletingPathExtension().lastPathComponent
            let ini = root.appendingPathComponent("\(id).ini")
            let config = readINI(dir.appendingPathComponent("config.ini"))
            let name = config["avd.ini.displayname"] ?? id.replacingOccurrences(of: "_", with: " ")
            // The disk images change whenever the emulator runs; the folder's
            // own date only changes when files are added or removed.
            let dates = ["userdata-qemu.img.qcow2", "userdata-qemu.img", "snapshots", "cache.img.qcow2"]
                .compactMap { FSUtil.lastModified(of: dir.appendingPathComponent($0)) }
                + [FSUtil.lastModified(of: dir)].compactMap { $0 }
            let locks = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).contains { $0.hasSuffix(".lock") }
            return VirtualDevice(
                name: name, dir: dir,
                ini: FSUtil.exists(ini.path) ? ini : nil,
                systemImage: config["image.sysdir.1"].map(normalizeImagePath),
                lastUsed: dates.max(),
                looksRunning: locks
            )
        }
    }

    static func scanEmulators(home: URL = FSUtil.home) -> [CleanableItem] {
        virtualDevices(home: home).compactMap { avd in
            let size = FSUtil.size(of: avd.dir)
            guard size > 50_000_000 else { return nil }
            let days = FSUtil.daysSince(avd.lastUsed)
            let used = days == Int.max ? "Never started" : days == 0 ? "Used today" : "Last used \(days) day\(days == 1 ? "" : "s") ago"
            var explanation = "\(used). Removing it deletes the emulator and the apps and data inside it; you can create a new one in Android Studio's Device Manager."
            if avd.looksRunning { explanation += " If this emulator is open, close it first." }
            return CleanableItem(
                name: "\(avd.name) emulator",
                path: avd.dir.path,
                paths: [avd.dir.path] + (avd.ini.map { [$0.path] } ?? []),
                sizeBytes: size,
                lastModified: avd.lastUsed,
                safety: .review,
                category: .androidEmulator,
                explanation: explanation,
                action: .trash
            )
        }
        .sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Installed system images no emulator uses. Images an emulator still
    /// points at are never offered — removing them would break that emulator.
    static func scanUnusedSystemImages(home: URL = FSUtil.home) -> [CleanableItem] {
        let sdk = sdkRoot(home: home)
        let imagesRoot = sdk.appendingPathComponent("system-images")
        guard FSUtil.exists(imagesRoot.path) else { return [] }
        let inUse = Set(virtualDevices(home: home).compactMap(\.systemImage))

        var items: [CleanableItem] = []
        for api in FSUtil.subdirectories(of: imagesRoot.path) {
            for tag in FSUtil.subdirectories(of: api.path) {
                for abi in FSUtil.subdirectories(of: tag.path) {
                    let relative = "system-images/\(api.lastPathComponent)/\(tag.lastPathComponent)/\(abi.lastPathComponent)"
                    guard !inUse.contains(relative) else { continue }
                    let size = FSUtil.size(of: abi)
                    guard size > 100_000_000 else { continue }
                    items.append(CleanableItem(
                        name: "\(describeAPI(api.lastPathComponent)) · \(describeTag(tag.lastPathComponent)) · \(abi.lastPathComponent)",
                        path: abi.path,
                        paths: [abi.path],
                        sizeBytes: size,
                        lastModified: FSUtil.lastModified(of: abi),
                        safety: .review,
                        category: .androidSystemImage,
                        explanation: "No emulator uses this system image. You can download it again from Android Studio's SDK Manager if you need it.",
                        action: .trash
                    ))
                }
            }
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    static func describeAPI(_ folder: String) -> String {
        guard folder.hasPrefix("android-") else { return folder }
        return "API \(folder.dropFirst("android-".count))"
    }

    static func describeTag(_ tag: String) -> String {
        switch tag {
        case "google_apis_playstore": return "Google Play"
        case "google_apis": return "Google APIs"
        case "default": return "AOSP"
        case "android-wear", "android-wear-cn": return "Wear OS"
        case "android-tv", "google-tv": return "TV"
        case "android-automotive", "android-automotive-playstore": return "Automotive"
        default: return tag.replacingOccurrences(of: "_", with: " ")
        }
    }

    static func scanCaches(home: URL = FSUtil.home) -> [CleanableItem] {
        var items: [CleanableItem] = []
        let studioRunning = NSRunningApplication.runningApplications(withBundleIdentifier: studioBundleID).isEmpty == false

        let sdkCache = home.appendingPathComponent(".android/cache")
        let sdkCacheSize = FSUtil.size(of: sdkCache)
        if sdkCacheSize > 5_000_000 {
            items.append(CleanableItem(
                name: "Android SDK download cache", path: sdkCache.path, paths: [sdkCache.path],
                sizeBytes: sdkCacheSize, lastModified: FSUtil.lastModified(of: sdkCache),
                safety: .regenerable, category: .androidCache,
                explanation: "Files the SDK Manager downloaded and has already installed. It downloads again only what it needs.",
                action: .trash
            ))
        }

        // Android Studio keeps one folder per version, e.g. AndroidStudio2024.2.
        let googleCaches = home.appendingPathComponent("Library/Caches/Google")
        let versions = FSUtil.subdirectories(of: googleCaches.path)
            .filter { $0.lastPathComponent.hasPrefix("AndroidStudio") }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
        for dir in versions {
            let size = FSUtil.size(of: dir)
            guard size > 20_000_000 else { continue }
            let isLatest = dir == versions.last
            // Don't pull indexes out from under a running IDE.
            if isLatest && studioRunning { continue }
            let version = dir.lastPathComponent.dropFirst("AndroidStudio".count)
            items.append(CleanableItem(
                name: "Android Studio \(version) caches", path: dir.path, paths: [dir.path],
                sizeBytes: size, lastModified: FSUtil.lastModified(of: dir),
                safety: .regenerable, category: .androidCache,
                explanation: isLatest
                    ? "Indexes and caches Android Studio rebuilds the next time you open a project. The first launch afterwards is a little slower."
                    : "Caches from an older version of Android Studio that's been replaced by a newer one.",
                action: .trash
            ))
        }

        // Settings and logs for Android Studio versions that have since been
        // replaced. Newer versions import settings once, on first launch, but
        // the user may still want them, so these are only offered for review.
        for folder in ["Library/Application Support/Google", "Library/Logs/Google"] {
            let parent = home.appendingPathComponent(folder)
            let dirs = FSUtil.subdirectories(of: parent.path)
                .filter { $0.lastPathComponent.hasPrefix("AndroidStudio") }
                .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
            for dir in dirs.dropLast() {
                let size = FSUtil.size(of: dir)
                guard size > 20_000_000 else { continue }
                let version = dir.lastPathComponent.dropFirst("AndroidStudio".count)
                let isLogs = folder.hasSuffix("Logs/Google")
                items.append(CleanableItem(
                    name: "Android Studio \(version) \(isLogs ? "logs" : "settings & plugins")", path: dir.path, paths: [dir.path],
                    sizeBytes: size, lastModified: FSUtil.lastModified(of: dir),
                    safety: isLogs ? .regenerable : .review, category: .androidCache,
                    explanation: isLogs
                        ? "Log files from an older version of Android Studio."
                        : "Settings and plugins for an older Android Studio version. A newer version is installed and imported them when it first opened.",
                    action: .trash
                ))
            }
        }
        return items.sorted { $0.sizeBytes > $1.sizeBytes }
    }
}
