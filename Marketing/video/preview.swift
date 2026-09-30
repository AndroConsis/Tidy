// Composes the App Store preview (1920×1080, 30 fps, H.264) from real Tidy
// footage recorded with `Tidy --record-demo raw.mov` (DEBUG builds only).
//
//   swiftc -O -o /tmp/tidy-preview Marketing/video/preview.swift
//   /tmp/tidy-preview <raw.mov> Marketing/video
//
// Apple guideline 2.3.4: previews may only use captures of the app, with text
// overlays. Everything below is either the recorded Tidy window, a real Tidy
// capture (the menu bar popover), captions, a pointer, or the app icon.
import AppKit
import AVFoundation
import CoreImage

let W: CGFloat = 1920, H: CGFloat = 1080, fps: Int32 = 30, duration = 26.0
let rawURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outDir = URL(fileURLWithPath: CommandLine.arguments[2]).absoluteURL
let repo = outDir.deletingLastPathComponent().deletingLastPathComponent()
let icon = NSImage(contentsOf: repo.appendingPathComponent("AppPackaging/Assets.xcassets/AppIcon.appiconset/icon_1024.png"))!
/// Recorded alongside the footage (same post-clean numbers).
let menu = NSImage(contentsOf: rawURL.deletingPathExtension().appendingPathExtension("menubar.png"))!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
func progress(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func window(_ t: Double, _ a: Double, _ b: Double, fade: Double = 0.35) -> Double { min(progress(t, a, a + fade), 1 - progress(t, b - fade, b)) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    return f.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? f
}
func text(_ s: String, at p: NSPoint, size: CGFloat, weight: NSFont.Weight = .heavy, color: NSColor = .white, alpha: Double) {
    guard alpha > 0.001 else { return }
    let str = NSAttributedString(string: s, attributes: [.font: font(size, weight), .foregroundColor: color.withAlphaComponent(color.alphaComponent * CGFloat(alpha))])
    let sz = str.size()
    str.draw(at: NSPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
}
func shadowed(_ blur: CGFloat, _ alpha: CGFloat, dy: CGFloat = -10, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: dy)
    s.shadowColor = NSColor.black.withAlphaComponent(alpha); s.set(); body()
    NSGraphicsContext.restoreGraphicsState()
}

// MARK: - Layout

let rawSize = CGSize(width: 1480, height: 884)
let scale: CGFloat = 0.98
let winRect = NSRect(x: (W - rawSize.width * scale) / 2, y: 34, width: rawSize.width * scale, height: rawSize.height * scale)
/// Camera keyframes: zoom, the raw-footage point kept at the frame's centre,
/// and a 3D tilt (0 = flat). The push-in during the clean follows the free
/// space as it grows.
let camera: [(t: Double, zoom: CGFloat, fx: CGFloat, fy: CGFloat, tilt: CGFloat)] = [
    (0.0, 1.00, 740, 442, 1.0), (2.7, 1.10, 700, 300, 0.0),
    (3.3, 1.12, 900, 250, 0.0), (7.6, 1.12, 900, 620, 0.0),
    (8.4, 1.30, 430, 300, 0.0), (11.5, 1.30, 430, 420, 0.0),
    (12.5, 1.00, 740, 442, 0.0), (13.7, 1.38, 560, 205, 0.0),
    (14.4, 1.48, 520, 180, 0.0), (16.8, 1.80, 420, 150, 0.0),
    (17.9, 1.00, 740, 442, 0.0), (18.9, 1.45, 700, 150, 0.0),
    (22.2, 1.50, 690, 150, 0.0), (23.0, 1.00, 740, 442, 0.55), (26.0, 1.00, 740, 442, 0.55),
]
/// Where the camera's focus point lands: the middle of the area below the captions.
let anchor = CGPoint(x: W / 2, y: 465)
func cameraState(_ t: Double) -> (zoom: CGFloat, f: CGPoint, tilt: CGFloat) {
    var zoom = camera.last!.zoom, f = CGPoint(x: camera.last!.fx, y: camera.last!.fy), tilt = camera.last!.tilt
    if t <= camera.first!.t {
        let c = camera.first!; zoom = c.zoom; f = CGPoint(x: c.fx, y: c.fy); tilt = c.tilt
    } else if let i = (0..<(camera.count - 1)).first(where: { t <= camera[$0 + 1].t }) {
        let a = camera[i], b = camera[i + 1], k = ease(progress(t, a.t, b.t))
        zoom = lerp(a.zoom, b.zoom, k); f = CGPoint(x: lerp(a.fx, b.fx, k), y: lerp(a.fy, b.fy, k)); tilt = lerp(a.tilt, b.tilt, k)
    }
    // Keep the frame covered: a window bigger than the frame never shows its
    // edges, and one smaller than the frame never slides partly off it.
    let k = scale * zoom
    func clampAxis(_ v: CGFloat, half: CGFloat, length: CGFloat) -> CGFloat {
        let lo = min(half / k, length - half / k), hi = max(half / k, length - half / k)
        return min(max(v, lo), hi)
    }
    f.x = clampAxis(f.x, half: anchor.x, length: rawSize.width)
    f.y = clampAxis(f.y, half: anchor.y, length: rawSize.height)
    return (zoom, f, tilt)
}
var cameraNow = cameraState(0)
/// Raw footage point (top-left origin) → canvas point, through the current camera.
func canvas(_ p: CGPoint) -> NSPoint {
    let k = scale * cameraNow.zoom
    return NSPoint(x: anchor.x + (p.x - cameraNow.f.x) * k, y: anchor.y - (p.y - cameraNow.f.y) * k)
}
/// Four corners of the footage on the canvas, with the 3D tilt applied
/// (left edge recedes, like the window turning towards the viewer).
func footageQuad() -> (tl: CGPoint, tr: CGPoint, br: CGPoint, bl: CGPoint) {
    let tl = canvas(.zero), br = canvas(CGPoint(x: rawSize.width, y: rawSize.height))
    let tilt = cameraNow.tilt, h = tl.y - br.y, w = br.x - tl.x
    let inset = h * 0.07 * tilt, shift = w * 0.06 * tilt
    return (CGPoint(x: tl.x + shift, y: tl.y - inset), CGPoint(x: br.x - shift * 0.3, y: tl.y + inset * 0.4),
            CGPoint(x: br.x - shift * 0.3, y: br.y - inset * 0.4), CGPoint(x: tl.x + shift, y: br.y + inset))
}

let captions: [(String, Double, Double)] = [
    ("Mac almost full?", 0.2, 3.0),
    ("Tidy finds what's really taking space", 3.0, 8.0),
    ("Every item marked Safe or Review", 8.0, 12.0),
    ("31 GB back in one click", 12.0, 18.3),
    ("Your photos and videos stay untouched", 18.3, 22.6),
    ("Always one click away in your menu bar", 22.6, 24.4),
]

/// Pointer keyframes in raw-footage points; `click` marks a press.
let pointer: [(t: Double, x: CGFloat, y: CGFloat, click: Bool)] = [
    (1.6, 760, 560, false), (2.85, 73, 118, false), (3.0, 73, 118, true),
    (7.0, 73, 118, false), (7.85, 90, 150, false), (8.0, 90, 150, true),
    (11.0, 90, 150, false), (11.85, 82, 86, false), (12.0, 82, 86, true),
    (12.6, 82, 86, false), (13.85, 330, 216, false), (14.2, 330, 216, true),
    (16.6, 330, 216, false), (18.3, 76, 278, false), (18.5, 76, 278, true),
    (19.2, 76, 278, false), (20.6, 620, 420, false),
]

func pointerState(_ t: Double) -> (NSPoint, Double, Double)? {
    guard t >= pointer.first!.t - 0.3, t <= 21.2 else { return nil }
    let alpha = min(progress(t, pointer.first!.t - 0.3, pointer.first!.t), 1 - progress(t, 20.7, 21.2))
    var pos = CGPoint(x: pointer.first!.x, y: pointer.first!.y)
    for i in 0..<(pointer.count - 1) {
        let a = pointer[i], b = pointer[i + 1]
        if t >= a.t && t <= b.t {
            let k = ease(progress(t, a.t, b.t))
            pos = CGPoint(x: lerp(a.x, b.x, k), y: lerp(a.y, b.y, k))
        } else if t > b.t { pos = CGPoint(x: b.x, y: b.y) }
    }
    var press = 0.0
    for k in pointer where k.click { press = max(press, 1 - min(abs(t - k.t) / 0.16, 1)) }
    return (canvas(pos), alpha, press)
}

func drawPointer(at p: NSPoint, alpha: Double, press: Double) {
    guard alpha > 0.01 else { return }
    let s: CGFloat = 1.25 * (1 - 0.12 * CGFloat(press))
    let path = NSBezierPath()
    let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, -26), (6, -20), (11, -31), (16, -29), (11, -18), (19, -18)]
    path.move(to: NSPoint(x: p.x, y: p.y))
    for (x, y) in pts.dropFirst() { path.line(to: NSPoint(x: p.x + x * s, y: p.y + y * s)) }
    path.close()
    shadowed(6, 0.5 * CGFloat(alpha), dy: -3) { NSColor.black.withAlphaComponent(CGFloat(alpha)).setFill(); path.fill() }
    let inner = NSBezierPath()
    let ipts: [(CGFloat, CGFloat)] = [(2, -4.5), (2, -21.5), (6.4, -17), (11.2, -27.7), (13.6, -26.7), (9, -16), (15, -16)]
    inner.move(to: NSPoint(x: p.x + ipts[0].0 * s, y: p.y + ipts[0].1 * s))
    for (x, y) in ipts.dropFirst() { inner.line(to: NSPoint(x: p.x + x * s, y: p.y + y * s)) }
    inner.close()
    NSColor.white.withAlphaComponent(CGFloat(alpha)).setFill(); inner.fill()
    if press > 0.01 {
        let r = 34 * CGFloat(1 - press) + 14
        rgb(0xFFFFFF, 0.35 * CGFloat(press) * CGFloat(alpha)).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)); ring.lineWidth = 3; ring.stroke()
    }
}

// MARK: - Frame composition

let ci = CIContext()
func drawFrame(_ t: Double, footage: CGImage?) {
    cameraNow = cameraState(t)
    NSGradient(starting: rgb(0x1B1240), ending: rgb(0x0A2A2D))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)
    NSGradient(colors: [rgb(0x8B5CF6, 0.45), rgb(0x8B5CF6, 0)])!
        .draw(fromCenter: NSPoint(x: 260, y: 1000), radius: 0, toCenter: NSPoint(x: 260, y: 1000), radius: 900, options: [])
    NSGradient(colors: [rgb(0x14B8A6, 0.35), rgb(0x14B8A6, 0)])!
        .draw(fromCenter: NSPoint(x: 1750, y: 80), radius: 0, toCenter: NSPoint(x: 1750, y: 80), radius: 900, options: [])


    if let footage {
        let q = footageQuad()
        shadowed(50, 0.55, dy: -16) {
            let quad = NSBezierPath()
            let inset: CGFloat = 16 * cameraNow.zoom
            quad.move(to: NSPoint(x: q.tl.x + inset, y: q.tl.y - inset)); quad.line(to: NSPoint(x: q.tr.x - inset, y: q.tr.y - inset))
            quad.line(to: NSPoint(x: q.br.x - inset, y: q.br.y + inset)); quad.line(to: NSPoint(x: q.bl.x + inset, y: q.bl.y + inset)); quad.close()
            rgb(0x000000).setFill(); quad.fill()
        }
        let cgctx = NSGraphicsContext.current!.cgContext
        cgctx.interpolationQuality = .high
        if cameraNow.tilt < 0.001 {
            cgctx.draw(footage, in: CGRect(x: q.bl.x, y: q.bl.y, width: q.br.x - q.bl.x, height: q.tl.y - q.bl.y))
        } else {
            let src = CIImage(cgImage: footage)
            let persp = CIFilter(name: "CIPerspectiveTransform", parameters: [
                kCIInputImageKey: src,
                "inputTopLeft": CIVector(cgPoint: q.tl), "inputTopRight": CIVector(cgPoint: q.tr),
                "inputBottomRight": CIVector(cgPoint: q.br), "inputBottomLeft": CIVector(cgPoint: q.bl),
            ])!.outputImage!
            let canvasRect = CGRect(x: 0, y: 0, width: W, height: H)
            if let img = ci.createCGImage(persp.cropped(to: canvasRect), from: persp.extent.intersection(canvasRect)) {
                cgctx.draw(img, in: persp.extent.intersection(canvasRect))
            }
        }
    }
    if let (p, a, press) = pointerState(t) { drawPointer(at: p, alpha: a, press: press) }

    // Menu bar popover beat — a real capture of Tidy's menu bar window.
    let menuA = window(t, 22.6, 24.6, fade: 0.3)
    if menuA > 0 {
        rgb(0x000000, 0.35 * CGFloat(menuA)).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()
        let rise = CGFloat(1 - ease(progress(t, 22.6, 23.1))) * 30
        let size = NSSize(width: 250 * 1.5, height: 244 * 1.5)
        let r = NSRect(x: winRect.maxX - size.width - 120, y: winRect.maxY - size.height - 70 + rise, width: size.width, height: size.height)
        shadowed(40, 0.55 * CGFloat(menuA)) {
            menu.draw(in: r, from: .zero, operation: .sourceOver, fraction: CGFloat(menuA))
        }
    }

    // Keep captions legible over zoomed footage.
    NSGradient(colors: [rgb(0x140E2E, 0.92), rgb(0x140E2E, 0)])!.draw(in: NSRect(x: 0, y: H - 190, width: W, height: 190), angle: -90)
    for (s, a, b) in captions {
        let al = window(t, a, b)
        text(s, at: NSPoint(x: W / 2, y: H - 88 + CGFloat(1 - al) * 12), size: 66, alpha: al)
    }

    // End card.
    let endA = ease(progress(t, 24.2, 24.8))
    if endA > 0 {
        NSGradient(starting: rgb(0x1B1240, CGFloat(endA)), ending: rgb(0x0A2A2D, CGFloat(endA)))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -35)
        let s = 260 * CGFloat(0.9 + 0.1 * ease(progress(t, 24.2, 25.0)))
        shadowed(40, 0.45 * CGFloat(endA)) {
            icon.draw(in: NSRect(x: W / 2 - s / 2, y: 560 - s / 2, width: s, height: s), from: .zero, operation: .sourceOver, fraction: CGFloat(endA))
        }
        text("Tidy", at: NSPoint(x: W / 2, y: 360), size: 104, alpha: progress(t, 24.5, 25.0))
        text("Mac Storage Cleaner", at: NSPoint(x: W / 2, y: 270), size: 46, weight: .semibold, color: rgb(0xFFFFFF, 0.8), alpha: progress(t, 24.6, 25.1))
    }
}

// MARK: - Read footage, write preview

let asset = AVURLAsset(url: rawURL)
let reader = try! AVAssetReader(asset: asset)
let rawTrack = asset.tracks(withMediaType: .video).first!
let readerOutput = AVAssetReaderTrackOutput(track: rawTrack, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(readerOutput)
reader.startReading()

let outURL = outDir.appendingPathComponent("Tidy-AppPreview.mp4")
try? FileManager.default.removeItem(at: outURL)
let writer = try! AVAssetWriter(outputURL: outURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(W), AVVideoHeightKey: Int(H),
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 14_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                      AVVideoExpectedSourceFrameRateKey: Int(fps), AVVideoMaxKeyFrameIntervalKey: Int(fps)],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(W), kCVPixelBufferHeightKey as String: Int(H),
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

var current: (t: Double, image: CGImage)?
var pending: CMSampleBuffer? = readerOutput.copyNextSampleBuffer()
func image(from sample: CMSampleBuffer) -> CGImage? {
    guard let pb = CMSampleBufferGetImageBuffer(sample) else { return nil }
    return ci.createCGImage(CIImage(cvPixelBuffer: pb), from: CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(pb), height: CVPixelBufferGetHeight(pb)))
}

let frames = Int(duration * Double(fps))
for i in 0..<frames {
    let t = Double(i) / Double(fps)
    // Advance to the latest recorded frame at or before t (the recording's timestamps are real time).
    while let s = pending, CMSampleBufferGetPresentationTimeStamp(s).seconds <= t {
        if let img = image(from: s) { current = (CMSampleBufferGetPresentationTimeStamp(s).seconds, img) }
        pending = readerOutput.copyNextSampleBuffer()
    }
    while !input.isReadyForMoreMediaData { usleep(2000) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    let buffer = pb!
    CVPixelBufferLockBaseAddress(buffer, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(W), height: Int(H), bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    drawFrame(t, footage: current?.image)
    NSGraphicsContext.restoreGraphicsState()
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
    if CommandLine.arguments.contains("--stills"), [45, 165, 300, 425, 465, 600, 700, 770].contains(i) {
        try! NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .jpeg, properties: [.compressionFactor: 0.85])!
            .write(to: URL(fileURLWithPath: CommandLine.arguments.last!.hasPrefix("--") ? "/tmp" : CommandLine.arguments.last!).appendingPathComponent("pv-\(i).jpg"))
    }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status == .completed ? "wrote \(outURL.path)" : "failed: \(String(describing: writer.error))")
