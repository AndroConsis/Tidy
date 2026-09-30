import Foundation

/// Shared filesystem helpers. Every scan in Tidy goes through these so
/// sizing and safety rules stay consistent across modules.
enum FSUtil {
    static let fm = FileManager.default

    /// The user's real home folder. Inside the sandbox,
    /// `homeDirectoryForCurrentUser` points at Tidy's own container instead.
    static let home: URL = {
        guard let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
    }()

    /// Absolute path to the active Xcode's `simctl`. `xcrun` refuses to run
    /// inside an App Sandbox, but calling `simctl` directly works. Returns nil
    /// when only the Command Line Tools (no simulators) are installed.
    static let simctlPath: String? = {
        var developerDirs: [String] = []
        // Unreadable inside the sandbox, but honoured when it isn't.
        if let link = try? fm.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link") {
            developerDirs.append(link)
        }
        let xcodes = ((try? fm.contentsOfDirectory(atPath: "/Applications")) ?? [])
            .filter { $0.hasPrefix("Xcode") && $0.hasSuffix(".app") }
            .sorted { $0 == "Xcode.app" || ($1 != "Xcode.app" && $0 < $1) }
        developerDirs += xcodes.map { "/Applications/\($0)/Contents/Developer" }
        return developerDirs
            .map { "\($0)/usr/bin/simctl" }
            .first { fm.isExecutableFile(atPath: $0) }
    }()

    /// Runs simctl and returns its JSON output. Inside the sandbox simctl
    /// prints an Xcode-license warning before the JSON, so everything before
    /// the first "{" is dropped.
    static func simctlJSON(_ args: [String]) -> Any? {
        guard let simctl = simctlPath else { return nil }
        let (status, output) = run(simctl, args)
        guard status == 0, let start = output.firstIndex(of: "{"),
              let data = String(output[start...]).data(using: .utf8)
        else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    /// Real on-disk size of a file or directory, in bytes.
    /// Does NOT follow into a different mounted volume (so a mounted
    /// simulator .dmg image isn't double-counted against its host size).
    static func size(of url: URL) -> Int64 {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue {
            let vals = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey])
            return Int64(vals?.totalFileAllocatedSize ?? vals?.fileAllocatedSize ?? 0)
        }

        var total: Int64 = 0
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .isDirectoryKey, .volumeURLKey]
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return 0 }

        for case let fileURL as URL in enumerator {
            guard let vals = try? fileURL.resourceValues(forKeys: Set(keys)) else { continue }
            if vals.isDirectory == true { continue }
            total += Int64(vals.totalFileAllocatedSize ?? vals.fileAllocatedSize ?? 0)
        }
        return total
    }

    static func lastModified(of url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }

    static func exists(_ path: String) -> Bool {
        fm.fileExists(atPath: path)
    }

    static func daysSince(_ date: Date?) -> Int {
        guard let date else { return Int.max }
        return Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? Int.max
    }

    /// Move a path to the Trash. Reversible via Finder "Put Back".
    static func trash(_ path: String) throws {
        let url = URL(fileURLWithPath: path)
        var result: NSURL?
        try fm.trashItem(at: url, resultingItemURL: &result)
    }

    /// List immediate subdirectories of a folder (non-recursive), skipping dotfiles.
    static func subdirectories(of path: String) -> [URL] {
        let url = URL(fileURLWithPath: path)
        guard let contents = try? fm.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
    }

    static func run(_ launchPath: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do {
            try p.run()
        } catch {
            return (-1, "failed to launch: \(error)")
        }
        p.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (p.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    }
}
