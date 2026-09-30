// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tidy",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Tidy",
            path: "Sources/Tidy",
            linkerSettings: [
                // Embeds AppPackaging/Info.plist directly into the raw
                // executable's __TEXT,__info_plist section. Without this,
                // Xcode's Run (⌘R) just drops a bare Mach-O binary into
                // DerivedData/.../Build/Products/Debug/ with no real .app
                // wrapper, so LaunchServices has nothing to build a bundle
                // proxy from and NSApplication startup (MenuBarExtra/Window
                // scenes) crashes with "bundleProxyForCurrentProcess is nil".
                // This makes the raw binary self-describing so ⌘R works
                // without needing the full build_app.sh bundle.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "AppPackaging/Info.plist"
                ])
            ]
        )
    ]
)
