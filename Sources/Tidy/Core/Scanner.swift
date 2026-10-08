import Foundation

/// Runs every module and assembles a ScanResult. Each module only looks at
/// its own allowlisted paths — Scanner never walks the filesystem freely.
enum Scanner {
    static func runFullScan() async -> ScanResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                var result = ScanResult()

                result.xcodeDeviceSupport = XcodeModule.scanDeviceSupport()
                result.xcodeSimulators = XcodeModule.scanSimulatorCaches()
                    + XcodeModule.scanSystemDyldCaches()
                    + XcodeModule.scanSimulatorRuntimes()
                    + XcodeModule.scanUnavailableDevices()
                    + XcodeModule.scanStaleDevices()
                result.xcodeBuildData = XcodeModule.scanDerivedData()
                    + XcodeModule.scanPreviews()
                    + XcodeModule.scanDocumentation()
                    + XcodeModule.scanArchives()

                result.android = AndroidModule.scanEmulators()
                    + AndroidModule.scanUnusedSystemImages()
                    + AndroidModule.scanCaches()

                result.devCaches = DevCachesModule.scan()
                    + DevCachesModule.scanStaleProjectArtifacts(under: [
                        FSUtil.home.appendingPathComponent("Projects").path
                    ])

                let installedIDs = InstallersModule.installedBundleIDs()
                result.appCaches = AppCachesModule.scanUpdaterLeftovers()
                    + AppCachesModule.scanGeneralCaches()
                    + AppCachesModule.scanOrphanedSupport(installedBundleIDs: installedIDs)

                result.installers = InstallersModule.scan()
                result.system = SystemModule.scan()

                continuation.resume(returning: result)
            }
        }
    }
}
