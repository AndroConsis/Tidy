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
        state.debugFreeBytes = Int64(18.6 * SampleData.gb)
        SampleData.fillFeatureModels(state)

        // Raw capture names stay the same as before the sidebar was grouped,
        // so Marketing/compose.swift keeps working.
        let shots: [(String, Section_, SubTab?, NSSize)] = [
            ("Overview", .overview, nil, NSSize(width: 1100, height: 560)),
            ("DiskMap", .diskMap, nil, NSSize(width: 1200, height: 720)),
            ("LargeFiles", .largeFiles, nil, NSSize(width: 1100, height: 640)),
            ("Apps", .apps, nil, NSSize(width: 1100, height: 600)),
            ("Xcode", .developer, .xcode, NSSize(width: 1180, height: 820)),
            ("Android", .developer, .android, NSSize(width: 1100, height: 560)),
            ("DevCaches", .developer, .packageCaches, NSSize(width: 1100, height: 620)),
            ("AppCaches", .junk, .appCaches, NSSize(width: 1100, height: 480)),
            ("Installers", .junk, .installers, NSSize(width: 1100, height: 420)),
            ("Trash", .junk, .trash, NSSize(width: 1100, height: 480)),
            ("System", .junk, .system, NSSize(width: 1100, height: 400)),
            ("Settings", .settings, nil, NSSize(width: 1100, height: 760)),
        ]
        NSApp.activate(ignoringOtherApps: true)
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let suffix = appearance == .darkAqua ? "dark" : "light"
            let only = ProcessInfo.processInfo.environment["TIDY_RENDER_ONLY"]
            for (name, section, tab, size) in shots where only == nil || only == name {
                let view = ContentView(initialSelection: section, initialTab: tab).environmentObject(state)
                await capture(view, size: size, appearance: appearance, titled: true,
                              to: dir.appendingPathComponent("\(name)-\(suffix).png"))
            }
            let menu = MenuBarView(openMainWindow: {})
                .environmentObject(state)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            await capture(menu, size: NSSize(width: 250, height: 290), appearance: appearance, titled: false,
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
        r.android = [
            item("Pixel 8 API 34 emulator", "\(home)/.android/avd/Pixel_8_API_34.avd", 9.84, .review, .androidEmulator,
                 "Last used 143 days ago. Removing it deletes the emulator and the apps and data inside it; you can create a new one in Android Studio's Device Manager.", daysAgo: 143),
            item("API 33 · Google Play · arm64-v8a", "\(home)/Library/Android/sdk/system-images/android-33/google_apis_playstore/arm64-v8a", 6.71, .review, .androidSystemImage,
                 "No emulator uses this system image. You can download it again from Android Studio's SDK Manager if you need it.", daysAgo: 260),
            item("Android Studio 2024.2 caches", "\(home)/Library/Caches/Google/AndroidStudio2024.2", 2.36, .regenerable, .androidCache,
                 "Indexes and caches Android Studio rebuilds the next time you open a project. The first launch afterwards is a little slower."),
            item("Android SDK download cache", "\(home)/.android/cache", 0.84, .regenerable, .androidCache,
                 "Files the SDK Manager downloaded and has already installed. It downloads again only what it needs."),
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
            item("com.streamly.player", "\(home)/Library/Caches/com.streamly.player", 1.38, .regenerable, .appCache, "App cache folder. macOS and the app rebuild caches automatically as needed."),
            item("com.chatwave.desktop", "\(home)/Library/Caches/com.chatwave.desktop", 0.72, .regenerable, .appCache, "App cache folder. macOS and the app rebuild caches automatically as needed."),
            item("com.canvasly.app", "\(home)/Library/Caches/com.canvasly.app", 0.46, .regenerable, .appCache, "App cache folder. macOS and the app rebuild caches automatically as needed."),
            item("com.lumenlabs.PhotoLab", "\(home)/Library/Application Support/com.lumenlabs.PhotoLab", 0.92, .review, .orphanedSupport,
                 "Leftover data for an app that's no longer installed (bundle ID com.lumenlabs.PhotoLab not found)."),
        ]
        r.system = [CleanableItem(
            name: "Photos Library", path: "\(home)/Pictures/Photos Library.photoslibrary", paths: [],
            sizeBytes: 0, lastModified: nil, safety: .personal, category: .system,
            explanation: "If iCloud Photos is on, turn on \"Optimize Mac Storage\" in Photos > Settings > iCloud instead of deleting anything. Full-size originals stay in iCloud and download on demand.",
            action: .guide("x-apple.systempreferences:com.apple.Photos-Settings.extension")
        ), CleanableItem(
            name: "3 local Time Machine snapshots", path: "", paths: [],
            sizeBytes: 0, lastModified: nil, safety: .personal, category: .system,
            explanation: "macOS manages these automatically and purges them when space runs low. Tidy won't remove them, since one may be your only local restore point.",
            action: .guide("")
        )]
        r.installers = [
            item("StudioSuite-2025-Installer.dmg", "\(home)/Downloads/StudioSuite-2025-Installer.dmg", 3.12, .review, .installer, "Looks like the installer for Studio Suite, which is already installed. The installer itself isn't needed anymore."),
            item("PixelForge-4.2.dmg", "\(home)/Downloads/PixelForge-4.2.dmg", 0.61, .review, .installer, "Looks like the installer for PixelForge, which is already installed. The installer itself isn't needed anymore."),
            item("Meetly-Setup.pkg", "\(home)/Downloads/Meetly-Setup.pkg", 0.23, .review, .installer, "Downloaded installer, untouched for 74 days."),
        ]
        return r
    }

    @MainActor
    static func fillFeatureModels(_ state: AppState) {
        let day: TimeInterval = 86_400
        func file(_ path: String, _ gigabytes: Double, opened: Double?, added: Double, kind: String, iCloud: Bool = false) -> LargeFilesModule.LargeFile {
            LargeFilesModule.LargeFile(url: URL(fileURLWithPath: "\(home)/\(path)"), sizeBytes: Int64(gigabytes * gb),
                                       lastOpened: opened.map { Date().addingTimeInterval(-$0 * day) },
                                       lastModified: Date().addingTimeInterval(-added * day), kind: kind, isInICloud: iCloud)
        }
        state.largeFiles.files = [
            file("Movies/Iceland trip raw footage.mov", 18.4, opened: 410, added: 430, kind: "QuickTime movie"),
            file("Downloads/linux-desktop-arm64.iso", 6.1, opened: nil, added: 220, kind: "Disk Image"),
            file("Documents/Backups/old-laptop-backup.zip", 4.7, opened: 600, added: 610, kind: "ZIP archive", iCloud: true),
            file("Desktop/Screen Recording 2026-03-14.mov", 2.9, opened: 205, added: 208, kind: "QuickTime movie"),
            file("Downloads/Course sample media.zip", 1.8, opened: nil, added: 96, kind: "ZIP archive"),
            file("Music/Podcast masters/Episode 12 master.wav", 1.2, opened: 30, added: 40, kind: "Waveform audio"),
            file("Movies/Wedding slideshow export.mp4", 0.9, opened: 12, added: 300, kind: "MPEG-4 movie"),
        ]
        state.largeFiles.lastScanDate = Date()

        typealias Node = DiskMapModule.Node
        func folder(_ name: String, _ gigabytes: Double, _ children: [Node]? = nil) -> Node {
            Node(url: URL(fileURLWithPath: "\(home)/\(name)"), name: name, isDirectory: true, size: Int64(gigabytes * gb), children: children)
        }
        let library = folder("Library", 61.2, [
            Node(url: URL(fileURLWithPath: "\(home)/Library/Developer"), isDirectory: true, size: Int64(34.1 * gb)),
            Node(url: URL(fileURLWithPath: "\(home)/Library/Caches"), isDirectory: true, size: Int64(9.4 * gb)),
            Node(url: URL(fileURLWithPath: "\(home)/Library/Application Support"), isDirectory: true, size: Int64(8.8 * gb)),
            Node(url: URL(fileURLWithPath: "\(home)/Library/Android"), isDirectory: true, size: Int64(6.7 * gb)),
        ])
        let root = Node(url: URL(fileURLWithPath: home), isDirectory: true, size: Int64(196 * gb), children: [
            library, folder("Pictures", 48.3), folder("Movies", 31.6), folder("Documents", 18.2), folder("Downloads", 14.9),
            folder(".android", 10.7), folder("Projects", 6.4), folder("Music", 4.1), folder(".gradle", 4.6), folder("Desktop", 3.2),
        ])
        root.otherSize = Int64(2.4 * gb)
        root.otherCount = 38
        state.diskMap.root = root
        state.diskMap.overview = DiskMapModule.Overview(total: Int64(494 * gb), free: Int64(18.6 * gb), apps: Int64(38 * gb), home: root.size)
        // Everyday story: the Downloads folder, with old installers to clear.
        state.diskMap.selected = root.children?.first { $0.name == "Downloads" }

        func app(_ name: String, _ gigabytes: Double, opened: Double?, version: String) -> UninstallerModule.InstalledApp {
            var a = UninstallerModule.InstalledApp(url: URL(fileURLWithPath: "/Applications/\(name).app"), name: name, bundleName: name,
                                                   bundleID: "com.example.\(name.lowercased().replacingOccurrences(of: " ", with: ""))",
                                                   version: version, lastOpened: opened.map { Date().addingTimeInterval(-$0 * day) },
                                                   isFromAppStore: false)
            a.sizeBytes = Int64(gigabytes * gb)
            return a
        }
        state.uninstaller.apps = [
            app("Studio Suite", 6.2, opened: 280, version: "2025.1"), app("PixelForge", 2.8, opened: 3, version: "4.2"),
            app("Meetly", 0.62, opened: 190, version: "6.0.4"), app("Notebook Pro", 0.41, opened: 1, version: "3.1"),
            app("Tunebox", 0.38, opened: 75, version: "1.9"), app("Sketchpad", 0.21, opened: nil, version: "2.0"),
        ]
        state.uninstaller.hasLoaded = true
        let iconStyles: [(String, NSColor, NSColor)] = [
            ("film.stack.fill", .systemIndigo, .systemPurple), ("paintbrush.pointed.fill", .systemOrange, .systemPink),
            ("video.fill", .systemTeal, .systemBlue), ("book.closed.fill", .systemYellow, .systemOrange),
            ("music.note", .systemPink, .systemRed), ("pencil.and.scribble", .systemGreen, .systemTeal),
        ]
        for (app, style) in zip(state.uninstaller.apps, iconStyles) {
            UninstallerModule.sampleIcons[app.url] = sampleIcon(symbol: style.0, from: style.1, to: style.2)
        }
    }

    /// A simple macOS-style app icon: a rounded gradient square with a symbol.
    static func sampleIcon(symbol: String, from: NSColor, to: NSColor) -> NSImage {
        NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            let tile = rect.insetBy(dx: 12, dy: 12)
            let path = NSBezierPath(roundedRect: tile, xRadius: 24, yRadius: 24)
            NSGradient(starting: from, ending: to)?.draw(in: path, angle: -60)
            if let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 50, weight: .semibold).applying(.init(paletteColors: [.white]))) {
                let size = glyph.size
                glyph.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            }
            return true
        }
    }

    static var recentActions: [LogEntry] {
        [("Uninstalled Studio Suite", 6.4, 0.2), ("Old installers", 3.1, 2), ("com.streamly.player", 1.4, 3),
         ("Leftovers of PhotoLab", 0.9, 9), ("Weatherly build data", 4.8, 12)]
            .map { name, size, daysAgo in
                LogEntry(date: Date().addingTimeInterval(-daysAgo * 86_400), name: name, paths: [], sizeBytes: Int64(size * gb), category: "")
            }
    }
}
#endif
