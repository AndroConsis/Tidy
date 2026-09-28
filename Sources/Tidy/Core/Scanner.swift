import Foundation

/// Runs every module and assembles a ScanResult. Each module only looks at
/// its own allowlisted paths — Scanner never walks the filesystem freely.
enum Scanner {
    static func hasFullDiskAccess() -> Bool {
        let probe = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Safari")
        return (try? FileManager.default.contentsOfDirectory(atPath: probe.path)) != nil
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
