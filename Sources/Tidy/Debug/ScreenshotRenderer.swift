#if DEBUG
import AppKit
import SwiftUI

/// Debug-only: `Tidy --render-screenshots <dir>` renders each main screen
/// with sample data (a fictional user, never the real disk) and saves 2x
/// PNGs of Tidy's own windows, for App Store screenshots. Not compiled into
/// Release builds.
@MainActor
enum ScreenshotRenderer {
    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--render-screenshots"), args.count > flag + 1 else { return false }
        let outDir = URL(fileURLWithPath: args[flag + 1], isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        Task { @MainActor in
            await render(to: outDir)
            NSApp.terminate(nil)
        }
        return true
    }

    private static func render(to dir: URL) async {
        FolderAccess.shared.pretendGrantedForScreenshots()
        let state = AppState()
        state.result = SampleData.result
        state.recentActions = SampleData.recentActions
        state.lastScanDate = Date().addingTimeInterval(-90)
        state.hasCompletedOnboarding = true

        let sizes: [Section_: NSSize] = [
            .overview: NSSize(width: 1100, height: 560),
            .xcode: NSSize(width: 1180, height: 800),
            .devCaches: NSSize(width: 1100, height: 580),
            .appCaches: NSSize(width: 1100, height: 440),
            .installers: NSSize(width: 1100, height: 380),
            .system: NSSize(width: 1100, height: 420),
            .settings: NSSize(width: 1100, height: 600),
        ]
        NSApp.activate(ignoringOtherApps: true)
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let suffix = appearance == .darkAqua ? "dark" : "light"
            for section in [Section_.overview, .xcode, .devCaches, .appCaches, .installers, .system, .settings] {
                let view = ContentView(initialSelection: section).environmentObject(state)
                await capture(view, size: sizes[section]!, appearance: appearance, titled: true,
                              to: dir.appendingPathComponent("\(section.id.replacingOccurrences(of: " ", with: ""))-\(suffix).png"))
            }
            let menu = MenuBarView(openMainWindow: {})
                .environmentObject(state)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            await capture(menu, size: NSSize(width: 250, height: 260), appearance: appearance, titled: false,
                          to: dir.appendingPathComponent("MenuBar-\(suffix).png"))
        }
    }

    static func capture(_ view: some View, size: NSSize, appearance: NSAppearance.Name, titled: Bool, to url: URL) async {
        let style: NSWindow.StyleMask = titled ? [.titled, .closable, .miniaturizable, .resizable] : [.borderless]
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size), styleMask: style, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Tidy"
        window.appearance = NSAppearance(named: appearance)
        window.backgroundColor = titled ? .windowBackgroundColor : .clear
        window.isOpaque = titled
        let host = NSHostingView(rootView: view)
        window.contentView = host
        if !titled {
            window.setContentSize(host.fittingSize)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(nanoseconds: 1_800_000_000)

        if titled, let image = compositedImage(of: window) {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
            window.close()
            return
        }
        guard let target = titled ? window.contentView?.superview : window.contentView else { return }
        let bounds = target.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return }
        rep.size = bounds.size
        target.cacheDisplay(in: bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}

/// The window exactly as the window server composites it, including the
/// Liquid Glass sidebar and toolbar that `cacheDisplay` can't draw. Looked up
/// at runtime because the SDK marks CGWindowListCreateImage unavailable; a
/// process may still capture its own windows without Screen Recording access.
func compositedImage(of window: NSWindow) -> CGImage? {
    typealias CreateImage = @convention(c) (CGRect, UInt32, CGWindowID, UInt32) -> Unmanaged<CGImage>?
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") else { return nil }
    let create = unsafeBitCast(symbol, to: CreateImage.self)
    let includingWindow: UInt32 = 1 << 3
    let boundsIgnoreFraming: UInt32 = 1 << 0
    let bestResolution: UInt32 = 1 << 3
    return create(.null, includingWindow, CGWindowID(window.windowNumber), boundsIgnoreFraming | bestResolution)?.takeRetainedValue()
}

enum SampleData {
    static let home = "/Users/alex"
    static let gb: Double = 1_000_000_000

    static func item(_ name: String, _ path: String, _ gigabytes: Double, _ safety: Safety, _ category: ItemCategory,
                     _ explanation: String, daysAgo: Double = 40, action: ItemAction = .trash) -> CleanableItem {
        CleanableItem(name: name, path: path, paths: [path], sizeBytes: Int64(gigabytes * gb),
                      lastModified: Date().addingTimeInterval(-daysAgo * 86_400), safety: safety,
                      category: category, explanation: explanation, action: action)
    }

    static let simctl = ["/Applications/Xcode.app/Contents/Developer/usr/bin/simctl"]

    static var result: ScanResult {
        var r = ScanResult()
        let dev = "\(home)/Library/Developer"
        r.xcodeDeviceSupport = [
            item("iOS iPhone16,2 17.5 (21F90)", "\(dev)/Xcode/iOS DeviceSupport/iPhone16,2 17.5 (21F90)", 4.21, .regenerable, .xcodeDeviceSupport,
                 "Superseded debug symbols for an older iOS version. Xcode re-copies them automatically if you debug on a device running that version again."),
            item("iOS iPhone15,3 17.2 (21C62)", "\(dev)/Xcode/iOS DeviceSupport/iPhone15,3 17.2 (21C62)", 3.86, .regenerable, .xcodeDeviceSupport,
                 "Superseded debug symbols for an older iOS version. Xcode re-copies them automatically if you debug on a device running that version again."),
        ]
        r.xcodeSimulators = [
            item("iOS 17.5 simulator runtime", "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime", 7.35, .review, .xcodeSimulatorRuntime,
                 "A newer iOS runtime is installed. Simulators on it stop working until you reinstall it from Xcode › Settings › Components.",
                 action: .command(simctl + ["runtime", "delete", "0"])),
            item("iPhone 15 Pro · iOS 17.5", "\(dev)/CoreSimulator/Devices/5E1D", 3.42, .review, .xcodeSimulatorDevice,
                 "Not booted in 96 days. Erasing wipes the apps and data installed in it; the simulator itself stays in Xcode's list.",
                 action: .command(simctl + ["erase", "0"])),
            item("watchOS 11.2 simulator dyld cache", "/Library/Developer/CoreSimulator/Caches/dyld", 2.64, .review, .xcodeSimulatorCache,
                 "Speeds up watchOS simulator launches. macOS rebuilds it automatically the next time one boots — worth removing only if you rarely use this runtime.",
                 action: .command(simctl + ["runtime", "dyld_shared_cache", "remove", "0"])),
            item("iPad Air (unavailable)", "\(dev)/CoreSimulator/Devices/9A3C", 1.18, .regenerable, .xcodeSimulatorDevice,
                 "Simulator device tied to a runtime that's no longer installed, so it can't boot anymore.",
                 action: .command(simctl + ["delete", "0"])),
        ]
        r.xcodeBuildData = [
            item("Weatherly build data", "\(dev)/Xcode/DerivedData/Weatherly-bxqk", 5.73, .regenerable, .xcodeDerivedData,
                 "Build products and index for a project not built in 58 days. Xcode rebuilds it the next time you open the project."),
            item("Checkout build data", "\(dev)/Xcode/DerivedData/Checkout-cfzm", 2.09, .review, .xcodeDerivedData,
                 "Build products and index for a project built 3 days ago — likely still in use. Removing it only means a full rebuild; quit Xcode first.", daysAgo: 3),
            item("ModuleCache.noindex", "\(dev)/Xcode/DerivedData/ModuleCache.noindex", 1.47, .regenerable, .xcodeDerivedData,
                 "Xcode's shared module/symbol cache. Rebuilt automatically on your next build."),
            item("Xcode documentation cache", "\(dev)/Xcode/DocumentationCache", 0.53, .regenerable, .xcodeDocumentation,
                 "Downloaded developer documentation. Xcode fetches pages again on demand when you open them."),
            item("Weatherly 2.3 (41)", "\(dev)/Xcode/Archives/2025-11-02/Weatherly 2.3.xcarchive", 0.41, .review, .xcodeArchive,
                 "An archived build from 312 days ago. Keep it if you may need to symbolicate crash reports from this build or re-export it."),
        ]
        r.devCaches = [
            item("Gradle cache", "\(home)/.gradle/caches", 4.62, .regenerable, .devCache, "Gradle re-downloads whatever it needs the next time you use it."),
            item("npm cache", "\(home)/.npm", 2.31, .regenerable, .devCache, "npm re-downloads whatever it needs the next time you use it."),
            item("Homebrew download cache", "\(home)/Library/Caches/Homebrew", 1.84, .regenerable, .devCache, "Homebrew re-downloads whatever it needs the next time you use it."),
            item("Yarn cache", "\(home)/Library/Caches/Yarn", 1.22, .regenerable, .devCache, "Yarn re-downloads whatever it needs the next time you use it."),
            item("CocoaPods cache", "\(home)/Library/Caches/CocoaPods", 0.89, .regenerable, .devCache, "CocoaPods re-downloads whatever it needs the next time you use it."),
            item("pip cache", "\(home)/Library/Caches/pip", 0.64, .regenerable, .devCache, "pip re-downloads whatever it needs the next time you use it."),
            item("landing-page/node_modules", "\(home)/Projects/landing-page/node_modules", 0.78, .review, .devCache,
                 "Dependency/build folder in a project untouched for 214 days. Reinstall with your package manager if you come back to it.", daysAgo: 214),
        ]
        r.appCaches = [
            item("com.spotify.client", "\(home)/Library/Caches/com.spotify.client", 1.38, .regenerable, .appCache, "App cache folder. macOS and the app rebuild caches automatically as needed."),
            item("com.tinyspeck.slackmacgap", "\(home)/Library/Caches/com.tinyspeck.slackmacgap", 0.72, .regenerable, .appCache, "App cache folder. macOS and the app rebuild caches automatically as needed."),
            item("com.figma.Desktop", "\(home)/Library/Caches/com.figma.Desktop", 0.46, .regenerable, .appCache, "App cache folder. macOS and the app rebuild caches automatically as needed."),
            item("com.lumenlabs.PhotoLab", "\(home)/Library/Application Support/com.lumenlabs.PhotoLab", 0.92, .review, .orphanedSupport,
                 "Leftover data for an app that's no longer installed (bundle ID com.lumenlabs.PhotoLab not found)."),
        ]
        r.system = [CleanableItem(
            name: "Photos Library", path: "\(home)/Pictures/Photos Library.photoslibrary", paths: [],
            sizeBytes: 0, lastModified: nil, safety: .personal, category: .system,
            explanation: "If iCloud Photos is on, turn on \"Optimize Mac Storage\" in Photos > Settings > iCloud instead of deleting anything. Full-size originals stay in iCloud and download on demand.",
            action: .guide("x-apple.systempreferences:com.apple.Photos-Settings.extension")
        )]
        r.installers = [
            item("Xcode_16.2.xip", "\(home)/Downloads/Xcode_16.2.xip", 3.12, .review, .installer, "Looks like the installer for Xcode, which is already installed. The installer itself isn't needed anymore."),
            item("Docker.dmg", "\(home)/Downloads/Docker.dmg", 0.61, .review, .installer, "Looks like the installer for Docker, which is already installed. The installer itself isn't needed anymore."),
            item("googlechrome.dmg", "\(home)/Downloads/googlechrome.dmg", 0.23, .review, .installer, "Downloaded installer, untouched for 74 days."),
        ]
        return r
    }

    static var recentActions: [LogEntry] {
        [("npm cache", 2.1, 0.2), ("Homebrew download cache", 1.6, 2), ("Weatherly build data", 4.8, 3),
         ("iOS iPhone14,5 16.4 (20E247)", 3.7, 9), ("com.spotify.client", 1.1, 12)]
            .map { name, size, daysAgo in
                LogEntry(date: Date().addingTimeInterval(-daysAgo * 86_400), name: name, paths: [], sizeBytes: Int64(size * gb), category: "")
            }
    }
}
#endif
