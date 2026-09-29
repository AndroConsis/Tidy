import Foundation

/// Runs every module and assembles a ScanResult. Each module only looks at
/// its own allowlisted paths — Scanner never walks the filesystem freely.
enum Scanner {
    static func hasFullDiskAccess() -> Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: probe.path)) != nil
    }

    /// Downloads and Desktop are the two macOS-protected folders InstallersModule
    /// reads. macOS shows its own "Tidy would like to access files in your
    /// Downloads folder" consent dialog the first time any process touches one —
    /// there's no Settings deep link for it like Full Disk Access, so the only
    /// way to surface it is to actually touch the folder once, deliberately.
    static let watchedFolderNames = ["Downloads", "Desktop"]

    static func hasFolderAccess() -> Bool {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return watchedFolderNames.allSatisfy { name in
            (try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(name).path)) != nil
        }
    }

    /// Touches Downloads and Desktop to trigger their consent dialogs. Call
    /// off the main thread — the first touch blocks until the user answers.
    static func requestFolderAccess() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for name in watchedFolderNames {
            _ = try? FileManager.default.contentsOfDirectory(atPath: home.appendingPathComponent(name).path)
        }
    }

    static func runFullScan() async -> ScanResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var result = ScanResult()

                result.xcodeDeviceSupport = XcodeModule.scanDeviceSupport()
                result.xcodeSimulators = XcodeModule.scanSimulatorCaches()
                    + XcodeModule.scanSimulatorRuntimes()
                    + XcodeModule.scanUnavailableDevices()
                result.xcodeBuildData = XcodeModule.scanDerivedData() + XcodeModule.scanPreviews()

                result.devCaches = DevCachesModule.scan()
                    + DevCachesModule.scanStaleProjectArtifacts(under: [
                        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Projects").path
                    ])

                let installedIDs = InstallersModule.installedBundleIDs()
                result.appCaches = AppCachesModule.scanUpdaterLeftovers()
                    + AppCachesModule.scanGeneralCaches()
                    + AppCachesModule.scanOrphanedSupport(installedBundleIDs: installedIDs)

                result.installers = InstallersModule.scan()
                result.unusedApps = UnusedAppsModule.scan()
                result.system = SystemModule.scan(hasFullDiskAccess: hasFullDiskAccess())
                    + PrivilegedToolsModule.scan()

                continuation.resume(returning: result)
            }
        }
    }
}
