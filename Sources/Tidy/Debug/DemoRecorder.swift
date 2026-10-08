#if DEBUG
import AppKit
import AVFoundation
import SwiftUI

extension Notification.Name {
    static let demoSelectSection = Notification.Name("TidyDemoSelectSection")
}

/// Debug-only: `Tidy --record-demo <file.mov>` plays a scripted walkthrough in
/// the real Tidy window (sample data for a nearly full Mac) and records that
/// window at 30 fps — genuine app footage for the App Store preview. Nothing is
/// actually cleaned. Not compiled into Release builds.
@MainActor
enum DemoRecorder {
    static let windowSize = NSSize(width: 1480, height: 800)
    static let duration = 22.5

    static func runIfRequested() -> Bool {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--record-demo"), args.count > flag + 1 else { return false }
        let url = URL(fileURLWithPath: args[flag + 1])
        Task { @MainActor in
            await record(to: url)
            NSApp.terminate(nil)
        }
        return true
    }

    private static func select(_ section: Section_, _ tab: SubTab? = nil) {
        NotificationCenter.default.post(name: .demoSelectSection, object: tab.map { (section, $0) } ?? section)
    }

    /// What "Clean all safe items" would do, without touching the disk.
    private static func simulateClean(_ state: AppState) {
        let freed = state.result.safeAutoCleanBytes
        let cleaned = state.result.all.filter { $0.safety == .regenerable }
        var r = state.result
        r.xcodeDeviceSupport.removeAll { $0.safety == .regenerable }
        r.xcodeSimulators.removeAll { $0.safety == .regenerable }
        r.xcodeBuildData.removeAll { $0.safety == .regenerable }
        r.devCaches.removeAll { $0.safety == .regenerable }
        r.appCaches.removeAll { $0.safety == .regenerable }
        state.result = r
        state.debugFreeBytes = (state.debugFreeBytes ?? 0) + freed
        state.recentActions = cleaned.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(5).map {
            LogEntry(date: Date(), name: $0.name, paths: [], sizeBytes: $0.sizeBytes, category: $0.category.rawValue)
        }
    }

    private static func record(to url: URL) async {
        FolderAccess.shared.pretendGrantedForScreenshots()
        let state = AppState()
        state.result = SampleData.result
        state.result.system = [CleanableItem(
            name: "Photos Library", path: "/Users/alex/Pictures/Photos Library.photoslibrary", paths: [],
            sizeBytes: 0, lastModified: nil, safety: .personal, category: .system,
            explanation: "If iCloud Photos is on, turn on \"Optimize Mac Storage\" in Photos > Settings > iCloud instead of deleting anything. Full-size originals stay in iCloud and download on demand.",
            action: .guide("x-apple.systempreferences:com.apple.Photos-Settings.extension")
        )]
        state.recentActions = []
        state.lastScanDate = Date().addingTimeInterval(-40)
        state.hasCompletedOnboarding = true
        state.debugFreeBytes = 8_200_000_000

        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 40, y: 40), size: windowSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "Tidy"
        window.appearance = NSAppearance(named: .darkAqua)
        window.contentView = NSHostingView(rootView: ContentView(initialSelection: .overview).environmentObject(state))
        // Footage of an inactive window (grey traffic lights, dimmed sidebar)
        // looks broken, so wait until Tidy is really frontmost.
        for _ in 0..<40 where !(NSApp.isActive && window.isKeyWindow) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard NSApp.isActive, window.isKeyWindow else { print("Tidy never became active; not recording"); return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        guard let first = compositedImage(of: window) else { print("capture failed"); return }
        let width = first.width, height = first.height
        try? FileManager.default.removeItem(at: url)
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.proRes422HQ, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = true
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        var events: [(Double, () -> Void)] = [
            (3.0, { select(.developer, .xcode) }),
            (8.0, { select(.developer, .packageCaches) }),
            (12.0, { select(.overview) }),
            (14.2, { simulateClean(state) }),
            (18.5, { select(.junk, .system) }),
        ]
        let start = CACurrentMediaTime()
        var frame = 0
        while true {
            let t = CACurrentMediaTime() - start
            if t >= duration { break }
            while let event = events.first, event.0 <= t { events.removeFirst(); event.1() }
            if input.isReadyForMoreMediaData, let image = compositedImage(of: window),
               image.width == width, image.height == height,
               let pool = adaptor.pixelBufferPool {
                var pb: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pb)
                if let buffer = pb {
                    CVPixelBufferLockBaseAddress(buffer, [])
                    if let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: width, height: height, bitsPerComponent: 8,
                                           bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
                        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
                        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                    }
                    CVPixelBufferUnlockBaseAddress(buffer, [])
                    adaptor.append(buffer, withPresentationTime: CMTime(seconds: t, preferredTimescale: 600))
                }
            }
            frame += 1
            let wait = start + Double(frame) / 30 - CACurrentMediaTime()
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
        }
        input.markAsFinished()
        await writer.finishWriting()
        print(writer.status == .completed ? "recorded \(frame) frames to \(url.path)" : "failed: \(String(describing: writer.error))")
        window.close()

        // The menu bar popover in the post-clean state, so its numbers match the footage.
        let menu = MenuBarView(openMainWindow: {})
            .environmentObject(state)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(nsColor: .windowBackgroundColor)))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        await ScreenshotRenderer.capture(menu, size: NSSize(width: 250, height: 260), appearance: .darkAqua, titled: false,
                                         to: url.deletingPathExtension().appendingPathExtension("menubar.png"))
    }
}
#endif
