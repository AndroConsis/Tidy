// Renders the animated "Keep your cool" story video (1920×1080, 30 fps, H.264).
//
//   swiftc -O -o /tmp/tidy-story Marketing/video/story.swift && /tmp/tidy-story Marketing/video
//
// Everything is drawn in code, so the video can be re-rendered after copy or
// timing changes. See SCRIPT.md for the storyboard.
import AppKit
import AVFoundation

let W: CGFloat = 1920, H: CGFloat = 1080, fps: Int32 = 30, duration: Double = 26
let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let repoRoot = outDir.absoluteURL.deletingLastPathComponent().deletingLastPathComponent()
let iconImage = NSImage(contentsOf: repoRoot.appendingPathComponent("AppPackaging/Assets.xcassets/AppIcon.appiconset/icon_1024.png"))
if iconImage == nil { fatalError("App icon not found under \(repoRoot.path)") }

// MARK: - Palette & helpers

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let violet = rgb(0x8B5CF6), teal = rgb(0x14B8A6), amber = rgb(0xF59E0B), coral = rgb(0xFB7185), hotRed = rgb(0xEF4444)
let skin = rgb(0xF2C6A0), hair = rgb(0x2B1B3F), shirt = rgb(0x7C5CE6)

func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(max(x, a), b) }
func progress(_ t: Double, _ a: Double, _ b: Double) -> Double { clamp((t - a) / (b - a)) }
func ease(_ x: Double) -> Double { x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2 }
func easeOutBack(_ x: Double) -> Double { let c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2) }
func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat { a + (b - a) * CGFloat(t) }
func mix(_ a: NSColor, _ b: NSColor, _ t: Double) -> NSColor {
    let a = a.usingColorSpace(.sRGB)!, b = b.usingColorSpace(.sRGB)!
    return NSColor(srgbRed: lerp(a.redComponent, b.redComponent, t), green: lerp(a.greenComponent, b.greenComponent, t),
                   blue: lerp(a.blueComponent, b.blueComponent, t), alpha: lerp(a.alphaComponent, b.alphaComponent, t))
}
/// Fades in over `a…a+0.5` and out over `b-0.5…b`.
func window(_ t: Double, _ a: Double, _ b: Double, fade: Double = 0.5) -> Double {
    min(progress(t, a, a + fade), 1 - progress(t, b - fade, b))
}

func font(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    return f.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? f
}
func text(_ s: String, at p: NSPoint, size: CGFloat, weight: NSFont.Weight = .bold, color: NSColor = .white, alpha: Double = 1, center: Bool = true) {
    guard alpha > 0.001 else { return }
    let attrs: [NSAttributedString.Key: Any] = [.font: font(size, weight), .foregroundColor: color.withAlphaComponent(color.alphaComponent * CGFloat(alpha))]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    str.draw(at: NSPoint(x: center ? p.x - sz.width / 2 : p.x, y: p.y - sz.height / 2))
}
func shadowed(_ blur: CGFloat, _ alpha: CGFloat, dy: CGFloat = -8, _ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: dy)
    s.shadowColor = NSColor.black.withAlphaComponent(alpha); s.set()
    body(); NSGraphicsContext.restoreGraphicsState()
}
func sparkle(_ c: NSPoint, _ r: CGFloat, _ color: NSColor = .white) {
    let p = NSBezierPath(), w: CGFloat = 0.16
    let pts = [NSPoint(x: c.x, y: c.y + r), NSPoint(x: c.x + r, y: c.y), NSPoint(x: c.x, y: c.y - r), NSPoint(x: c.x - r, y: c.y)]
    p.move(to: pts[0])
    for i in 0..<4 {
        let a = pts[i], b = pts[(i + 1) % 4]
        p.curve(to: b, controlPoint1: NSPoint(x: c.x + (a.x - c.x) * w, y: c.y + (a.y - c.y) * w),
                controlPoint2: NSPoint(x: c.x + (b.x - c.x) * w, y: c.y + (b.y - c.y) * w))
    }
    color.setFill(); p.fill()
}

// MARK: - Story timing

/// 0 = hot and stressed, 1 = cool and calm.
func calm(_ t: Double) -> Double { ease(progress(t, 12.5, 16.5)) }
/// Storage fill, 97% → 45% while Tidy sweeps.
func fill(_ t: Double) -> Double { 0.97 - 0.52 * ease(progress(t, 11.0, 14.2)) }

// MARK: - Characters & props

func drawBackground(_ t: Double) {
    let c = calm(t)
    let top = mix(rgb(0x3A1420), rgb(0x1B1240), c), bottom = mix(rgb(0x5A1E14), rgb(0x0A2A2D), c)
    NSGradient(starting: top, ending: bottom)!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -90)
    // Warm glow early, cool glow later.
    let glowColor = mix(rgb(0xFF6B3D, 0.35), rgb(0x14B8A6, 0.28), c)
    NSGradient(colors: [glowColor, glowColor.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 760, y: 470), radius: 0, toCenter: NSPoint(x: 760, y: 470), radius: 700, options: [])
    // Desk.
    rgb(0x000000, 0.22).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: 210)).fill()
    rgb(0xFFFFFF, 0.06).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 208, width: W, height: 3)).fill()
}

func drawHeatWaves(_ t: Double, center: NSPoint) {
    let heat = 1 - calm(t)
    guard heat > 0.01 else { return }
    for i in 0..<5 {
        let x = center.x - 220 + CGFloat(i) * 110
        let phase = t * 3 + Double(i) * 1.3
        let rise = CGFloat((t * 60 + Double(i) * 37).truncatingRemainder(dividingBy: 120))
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x, y: center.y + 250 + rise))
        for s in 1...6 {
            let y = center.y + 250 + rise + CGFloat(s) * 28
            p.line(to: NSPoint(x: x + CGFloat(sin(phase + Double(s))) * 18, y: y))
        }
        p.lineWidth = 7; p.lineCapStyle = .round
        rgb(0xFF8A4C, 0.55 * heat * (1 - Double(rise) / 140)).setStroke(); p.stroke()
    }
}

func drawBreeze(_ t: Double) {
    let c = calm(t)
    guard c > 0.01 else { return }
    for i in 0..<4 {
        let y = 640 + CGFloat(i) * 70
        let x = CGFloat((t * 240 + Double(i) * 400).truncatingRemainder(dividingBy: 2400)) - 300
        let p = NSBezierPath()
        p.move(to: NSPoint(x: x, y: y))
        p.curve(to: NSPoint(x: x + 260, y: y + 10), controlPoint1: NSPoint(x: x + 80, y: y + 30), controlPoint2: NSPoint(x: x + 170, y: y - 20))
        p.lineWidth = 5; p.lineCapStyle = .round
        rgb(0xBFF6EE, 0.35 * c).setStroke(); p.stroke()
    }
}

func drawThermometer(_ t: Double, at o: NSPoint) {
    let heat = 1 - calm(t)
    let tube = NSBezierPath(roundedRect: NSRect(x: o.x - 18, y: o.y, width: 36, height: 190), xRadius: 18, yRadius: 18)
    rgb(0xFFFFFF, 0.9).setFill(); tube.fill()
    let bulb = NSBezierPath(ovalIn: NSRect(x: o.x - 32, y: o.y - 40, width: 64, height: 64))
    let color = mix(teal, hotRed, heat)
    rgb(0xFFFFFF, 0.9).setFill(); bulb.fill()
    color.setFill()
    NSBezierPath(ovalIn: NSRect(x: o.x - 22, y: o.y - 30, width: 44, height: 44)).fill()
    let level = 20 + 150 * CGFloat(0.25 + 0.75 * heat)
    NSBezierPath(roundedRect: NSRect(x: o.x - 9, y: o.y, width: 18, height: level), xRadius: 9, yRadius: 9).fill()
}

func drawLaptop(_ t: Double, center c: NSPoint) {
    let heat = 1 - calm(t)
    let shake = CGFloat(heat > 0.5 ? sin(t * 40) * 3 * heat : 0)
    let o = NSPoint(x: c.x + shake, y: c.y)
    // Base.
    let base = NSBezierPath()
    base.move(to: NSPoint(x: o.x - 330, y: o.y - 180)); base.line(to: NSPoint(x: o.x + 330, y: o.y - 180))
    base.line(to: NSPoint(x: o.x + 290, y: o.y - 150)); base.line(to: NSPoint(x: o.x - 290, y: o.y - 150)); base.close()
    shadowed(30, 0.35) { rgb(0xC9CCD6).setFill(); base.fill() }
    // Lid.
    let lidRect = NSRect(x: o.x - 280, y: o.y - 150, width: 560, height: 360)
    let lid = NSBezierPath(roundedRect: lidRect, xRadius: 26, yRadius: 26)
    shadowed(40, 0.35) { mix(rgb(0xD6D9E2), rgb(0xE9D2D2), heat * 0.6).setFill(); lid.fill() }
    let screenRect = lidRect.insetBy(dx: 22, dy: 22)
    let screen = NSBezierPath(roundedRect: screenRect, xRadius: 12, yRadius: 12)
    mix(rgb(0x1E1B2E), rgb(0x2A1216), heat).setFill(); screen.fill()

    // Face (top half of the screen).
    let fc = NSPoint(x: o.x, y: screenRect.maxY - 110)
    let eyeY = fc.y + 14
    rgb(0xFFFFFF).setFill(); rgb(0xFFFFFF).setStroke()
    if heat > 0.5 {
        // Stressed: wide eyes, slanted brows, wobbly frown, sweat.
        for dx in [-80.0, 80.0] {
            NSBezierPath(ovalIn: NSRect(x: fc.x + CGFloat(dx) - 16, y: eyeY - 20, width: 32, height: 40)).fill()
            let brow = NSBezierPath(); brow.lineWidth = 8; brow.lineCapStyle = .round
            brow.move(to: NSPoint(x: fc.x + CGFloat(dx) - 30, y: eyeY + 42 + (dx < 0 ? -10 : 10)))
            brow.line(to: NSPoint(x: fc.x + CGFloat(dx) + 30, y: eyeY + 42 + (dx < 0 ? 10 : -10)))
            brow.stroke()
        }
        let m = NSBezierPath(); m.lineWidth = 9; m.lineCapStyle = .round
        m.move(to: NSPoint(x: fc.x - 60, y: fc.y - 62))
        for s in 1...6 { m.line(to: NSPoint(x: fc.x - 60 + CGFloat(s) * 20, y: fc.y - 62 + (s % 2 == 0 ? 0 : 10))) }
        m.stroke()
        // Sweat drops.
        for (i, dx) in [(0, -200.0), (1, 190.0)] {
            let fall = CGFloat((t * 70 + Double(i) * 50).truncatingRemainder(dividingBy: 90))
            let d = NSBezierPath()
            let dp = NSPoint(x: fc.x + CGFloat(dx), y: fc.y + 60 - fall)
            d.move(to: NSPoint(x: dp.x, y: dp.y + 26))
            d.curve(to: NSPoint(x: dp.x, y: dp.y - 10), controlPoint1: NSPoint(x: dp.x + 22, y: dp.y), controlPoint2: NSPoint(x: dp.x + 16, y: dp.y - 10))
            d.curve(to: NSPoint(x: dp.x, y: dp.y + 26), controlPoint1: NSPoint(x: dp.x - 16, y: dp.y - 10), controlPoint2: NSPoint(x: dp.x - 22, y: dp.y))
            rgb(0x7DD3FC, 0.9 * (1 - Double(fall) / 90)).setFill(); d.fill()
        }
        // Blush.
        rgb(0xFF5A5A, 0.45 * heat).setFill()
        for dx in [-140.0, 140.0] { NSBezierPath(ovalIn: NSRect(x: fc.x + CGFloat(dx) - 30, y: fc.y - 30, width: 60, height: 26)).fill() }
    } else {
        // Calm: happy closed eyes and a smile.
        for dx in [-80.0, 80.0] {
            let e = NSBezierPath(); e.lineWidth = 9; e.lineCapStyle = .round
            e.appendArc(withCenter: NSPoint(x: fc.x + CGFloat(dx), y: eyeY - 6), radius: 22, startAngle: 20, endAngle: 160)
            e.stroke()
        }
        let m = NSBezierPath(); m.lineWidth = 10; m.lineCapStyle = .round
        m.appendArc(withCenter: NSPoint(x: fc.x, y: fc.y - 30), radius: 48, startAngle: 200, endAngle: 340)
        m.stroke()
        rgb(0x5EEAD4, 0.35).setFill()
        for dx in [-140.0, 140.0] { NSBezierPath(ovalIn: NSRect(x: fc.x + CGFloat(dx) - 30, y: fc.y - 30, width: 60, height: 26)).fill() }
    }

    // Storage bar (bottom half of the screen).
    let f = fill(t)
    let bar = NSRect(x: screenRect.minX + 40, y: screenRect.minY + 44, width: screenRect.width - 80, height: 30)
    rgb(0xFFFFFF, 0.14).setFill(); NSBezierPath(roundedRect: bar, xRadius: 15, yRadius: 15).fill()
    let fillRect = NSRect(x: bar.minX, y: bar.minY, width: bar.width * CGFloat(f), height: bar.height)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: fillRect, xRadius: 15, yRadius: 15).addClip()
    let hot = progress(f, 0.6, 0.9)
    NSGradient(starting: mix(teal, amber, hot), ending: mix(rgb(0x2DD4BF), hotRed, hot))!.draw(in: fillRect, angle: 0)
    NSGraphicsContext.restoreGraphicsState()
    let pct = Int((f * 100).rounded())
    let warn = f > 0.9 && Int(t * 3) % 2 == 0
    text("\(warn ? "⚠︎ " : "")Macintosh HD — \(pct)% full", at: NSPoint(x: bar.midX, y: bar.maxY + 30), size: 28, weight: .semibold,
         color: f > 0.9 ? rgb(0xFFB4A0) : rgb(0xCCFBF1))
}

func drawPerson(_ t: Double, center o: NSPoint) {
    let c = calm(t)
    let bob = CGFloat(sin(t * (c > 0.5 ? 2 : 9)) * (c > 0.5 ? 4 : 2))
    // Body.
    let body = NSBezierPath(roundedRect: NSRect(x: o.x - 110, y: o.y - 180 + bob, width: 220, height: 230), xRadius: 90, yRadius: 90)
    shadowed(24, 0.3) { shirt.setFill(); body.fill() }
    // Head.
    let head = NSPoint(x: o.x, y: o.y + 140 + bob)
    shadowed(20, 0.25) { skin.setFill(); NSBezierPath(ovalIn: NSRect(x: head.x - 95, y: head.y - 95, width: 190, height: 190)).fill() }
    hair.setFill()
    let hairPath = NSBezierPath()
    hairPath.appendArc(withCenter: head, radius: 98, startAngle: 10, endAngle: 170)
    hairPath.curve(to: NSPoint(x: head.x + 96, y: head.y + 16), controlPoint1: NSPoint(x: head.x - 40, y: head.y + 50), controlPoint2: NSPoint(x: head.x + 40, y: head.y + 70))
    hairPath.fill()
    let ink = rgb(0x2B1B3F)
    ink.setFill(); ink.setStroke()
    if c < 0.5 {
        for dx in [-34.0, 34.0] { NSBezierPath(ovalIn: NSRect(x: head.x + CGFloat(dx) - 9, y: head.y - 14, width: 18, height: 22)).fill() }
        for dx in [-34.0, 34.0] {
            let b = NSBezierPath(); b.lineWidth = 6; b.lineCapStyle = .round
            b.move(to: NSPoint(x: head.x + CGFloat(dx) - 18, y: head.y + 22 + (dx < 0 ? -6 : 6)))
            b.line(to: NSPoint(x: head.x + CGFloat(dx) + 18, y: head.y + 22 + (dx < 0 ? 6 : -6))); b.stroke()
        }
        let m = NSBezierPath(); m.lineWidth = 6; m.lineCapStyle = .round
        m.appendArc(withCenter: NSPoint(x: head.x, y: head.y - 62), radius: 26, startAngle: 30, endAngle: 150); m.stroke()
        // Stress squiggle.
        let s = NSBezierPath(); s.lineWidth = 6; s.lineCapStyle = .round
        s.move(to: NSPoint(x: head.x + 110, y: head.y + 90))
        for k in 1...4 { s.line(to: NSPoint(x: head.x + 110 + CGFloat(k) * 14, y: head.y + 90 + (k % 2 == 0 ? 0 : 18))) }
        rgb(0xFFFFFF, 0.8).setStroke(); s.stroke()
    } else {
        for dx in [-34.0, 34.0] {
            let e = NSBezierPath(); e.lineWidth = 6; e.lineCapStyle = .round
            e.appendArc(withCenter: NSPoint(x: head.x + CGFloat(dx), y: head.y - 6), radius: 14, startAngle: 20, endAngle: 160); e.stroke()
        }
        let m = NSBezierPath(); m.lineWidth = 7; m.lineCapStyle = .round
        m.appendArc(withCenter: NSPoint(x: head.x, y: head.y - 30), radius: 30, startAngle: 210, endAngle: 330); m.stroke()
        // Coffee mug with steam.
        let mugA = progress(t, 16, 16.8)
        if mugA > 0 {
            let mug = NSRect(x: o.x + 70, y: o.y - 70 + bob, width: 80, height: 90)
            rgb(0xFFFFFF, mugA).setFill(); NSBezierPath(roundedRect: mug, xRadius: 14, yRadius: 14).fill()
            let handle = NSBezierPath(); handle.lineWidth = 12
            handle.appendArc(withCenter: NSPoint(x: mug.maxX, y: mug.midY), radius: 22, startAngle: -70, endAngle: 70)
            rgb(0xFFFFFF, mugA).setStroke(); handle.stroke()
            teal.withAlphaComponent(mugA).setFill(); NSBezierPath(rect: NSRect(x: mug.minX, y: mug.minY + 36, width: mug.width, height: 14)).fill()
            for k in 0..<2 {
                let st = NSBezierPath(); st.lineWidth = 5; st.lineCapStyle = .round
                let sx = mug.midX - 16 + CGFloat(k) * 30
                st.move(to: NSPoint(x: sx, y: mug.maxY + 10))
                st.curve(to: NSPoint(x: sx, y: mug.maxY + 70), controlPoint1: NSPoint(x: sx + 18 * CGFloat(sin(t * 3 + Double(k))), y: mug.maxY + 30),
                         controlPoint2: NSPoint(x: sx - 18, y: mug.maxY + 50))
                rgb(0xFFFFFF, 0.5 * mugA).setStroke(); st.stroke()
            }
        }
    }
}

func drawPhotoCard(at p: NSPoint, size s: CGFloat, video: Bool, alpha: Double) {
    guard alpha > 0.01 else { return }
    let r = NSRect(x: p.x - s / 2, y: p.y - s * 0.4, width: s, height: s * 0.8)
    shadowed(14, 0.3 * alpha) {
        rgb(0xFFFFFF, alpha).setFill(); NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).fill()
    }
    let inner = r.insetBy(dx: 8, dy: 8)
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(roundedRect: inner, xRadius: 8, yRadius: 8).addClip()
    NSGradient(starting: rgb(0x7DD3FC, alpha), ending: rgb(0xC4B5FD, alpha))!.draw(in: inner, angle: -90)
    let hill = NSBezierPath()
    hill.move(to: NSPoint(x: inner.minX, y: inner.minY)); hill.line(to: NSPoint(x: inner.minX + inner.width * 0.35, y: inner.midY))
    hill.line(to: NSPoint(x: inner.minX + inner.width * 0.6, y: inner.minY + inner.height * 0.3))
    hill.line(to: NSPoint(x: inner.maxX, y: inner.midY + 10)); hill.line(to: NSPoint(x: inner.maxX, y: inner.minY)); hill.close()
    rgb(0x16A34A, alpha).setFill(); hill.fill()
    rgb(0xFDE047, alpha).setFill(); NSBezierPath(ovalIn: NSRect(x: inner.maxX - s * 0.28, y: inner.maxY - s * 0.26, width: s * 0.16, height: s * 0.16)).fill()
    NSGraphicsContext.restoreGraphicsState()
    if video {
        rgb(0x000000, 0.45 * alpha).setFill(); NSBezierPath(ovalIn: NSRect(x: r.midX - 22, y: r.midY - 22, width: 44, height: 44)).fill()
        let tri = NSBezierPath(); tri.move(to: NSPoint(x: r.midX - 7, y: r.midY - 12)); tri.line(to: NSPoint(x: r.midX + 13, y: r.midY)); tri.line(to: NSPoint(x: r.midX - 7, y: r.midY + 12)); tri.close()
        rgb(0xFFFFFF, alpha).setFill(); tri.fill()
    }
}

func drawTrash(at p: NSPoint, alpha: Double) {
    guard alpha > 0.01 else { return }
    let body = NSBezierPath()
    body.move(to: NSPoint(x: p.x - 70, y: p.y + 70)); body.line(to: NSPoint(x: p.x + 70, y: p.y + 70))
    body.line(to: NSPoint(x: p.x + 55, y: p.y - 80)); body.line(to: NSPoint(x: p.x - 55, y: p.y - 80)); body.close()
    rgb(0xE5E7EB, alpha).setFill(); body.fill()
    rgb(0xD1D5DB, alpha).setFill(); NSBezierPath(roundedRect: NSRect(x: p.x - 85, y: p.y + 70, width: 170, height: 22), xRadius: 8, yRadius: 8).fill()
    for dx in [-30.0, 0, 30] {
        let l = NSBezierPath(); l.lineWidth = 6; l.lineCapStyle = .round
        l.move(to: NSPoint(x: p.x + CGFloat(dx), y: p.y + 45)); l.line(to: NSPoint(x: p.x + CGFloat(dx) * 0.8, y: p.y - 55))
        rgb(0x9CA3AF, alpha).setStroke(); l.stroke()
    }
}

func drawTidyIcon(at p: NSPoint, size s: CGFloat, alpha: Double) {
    guard alpha > 0.01, let icon = iconImage else { return }
    shadowed(30, 0.4 * alpha) {
        icon.draw(in: NSRect(x: p.x - s / 2, y: p.y - s / 2, width: s, height: s), from: .zero, operation: .sourceOver, fraction: CGFloat(alpha))
    }
}

func drawJunkBubble(_ label: String, at p: NSPoint, scale: CGFloat, alpha: Double) {
    guard alpha > 0.01, scale > 0.02 else { return }
    let str = NSAttributedString(string: label, attributes: [.font: font(30 * scale, .bold), .foregroundColor: rgb(0x3B1D00, alpha)])
    let sz = str.size()
    let r = NSRect(x: p.x - sz.width / 2 - 26 * scale, y: p.y - 30 * scale, width: sz.width + 52 * scale, height: 60 * scale)
    shadowed(16, 0.3 * alpha) {
        NSGradient(starting: rgb(0xFCD34D, alpha), ending: rgb(0xF59E0B, alpha))!.draw(in: NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2), angle: -90)
    }
    str.draw(at: NSPoint(x: p.x - sz.width / 2, y: p.y - sz.height / 2))
}

// MARK: - Frame

let laptopC = NSPoint(x: 760, y: 430)
let personC = NSPoint(x: 1430, y: 350)
let tidyHome = NSPoint(x: 1090, y: 790)
let junk: [(String, NSPoint)] = [("Xcode caches 18 GB", NSPoint(x: 300, y: 720)), ("npm cache 2 GB", NSPoint(x: 1560, y: 820)),
                                 ("Old installers 3 GB", NSPoint(x: 260, y: 470)), ("App caches 4 GB", NSPoint(x: 330, y: 230))]

/// Camera: zoom and the scene point kept at the frame's centre. It drifts in on
/// the stressed laptop, leans towards the trash, then pushes in on the storage
/// bar while it drains, and pulls back for the calm ending.
let storyCamera: [(t: Double, zoom: CGFloat, fx: CGFloat, fy: CGFloat)] = [
    (0.0, 1.00, 960, 520), (4.8, 1.10, 820, 500), (5.6, 1.10, 700, 500), (8.8, 1.14, 640, 480),
    (10.4, 1.00, 960, 540), (11.2, 1.05, 900, 520), (14.2, 1.50, 760, 405), (15.4, 1.50, 760, 405),
    (16.8, 1.00, 960, 520), (20.8, 1.10, 1080, 470), (26.0, 1.10, 1080, 470),
]
func cameraTransform(_ t: Double) -> NSAffineTransform {
    var zoom = storyCamera.last!.zoom, fx = storyCamera.last!.fx, fy = storyCamera.last!.fy
    if let i = (0..<(storyCamera.count - 1)).first(where: { t <= storyCamera[$0 + 1].t }) {
        let a = storyCamera[i], b = storyCamera[i + 1], k = ease(progress(t, a.t, b.t))
        zoom = lerp(a.zoom, b.zoom, k); fx = lerp(a.fx, b.fx, k); fy = lerp(a.fy, b.fy, k)
    }
    let xf = NSAffineTransform()
    xf.translateX(by: W / 2, yBy: 520)
    xf.scale(by: zoom)
    xf.translateX(by: -fx, yBy: -fy)
    return xf
}

func drawFrame(_ t: Double) {
    NSGraphicsContext.saveGraphicsState()
    cameraTransform(t).concat()
    drawBackground(t)
    drawBreeze(t)
    drawHeatWaves(t, center: laptopC)
    drawThermometer(t, at: NSPoint(x: 1120, y: 300))
    drawLaptop(t, center: laptopC)
    drawPerson(t, center: personC)

    // Scene 2 — photos drift to the trash, then get saved.
    let trashA = window(t, 5.0, 9.3)
    drawTrash(at: NSPoint(x: 290, y: 330), alpha: trashA)
    let drift = ease(progress(t, 5.4, 7.0))
    let rescue = ease(progress(t, 7.6, 8.8))
    for i in 0..<4 {
        let start = NSPoint(x: laptopC.x - 150 + CGFloat(i) * 100, y: laptopC.y + 40)
        let nearTrash = NSPoint(x: 290 + CGFloat(i - 2) * 40, y: 470 + CGFloat(i % 2) * 30)
        let saved = NSPoint(x: laptopC.x - 150 + CGFloat(i) * 100, y: 760 + CGFloat(i % 2) * 20)
        var pt = NSPoint(x: lerp(start.x, nearTrash.x, drift), y: lerp(start.y, nearTrash.y, drift) + CGFloat(sin(t * 4 + Double(i))) * 6)
        pt = NSPoint(x: lerp(pt.x, saved.x, rescue), y: lerp(pt.y, saved.y, rescue))
        drawPhotoCard(at: pt, size: 120, video: i == 2, alpha: window(t, 5.2, 9.4))
    }
    let xA = window(t, 6.9, 8.6, fade: 0.25)
    if xA > 0 {
        let s = CGFloat(easeOutBack(progress(t, 6.9, 7.3)))
        let x = NSBezierPath(); x.lineWidth = 34 * s; x.lineCapStyle = .round
        let c = NSPoint(x: 290, y: 400)
        x.move(to: NSPoint(x: c.x - 110 * s, y: c.y - 110 * s)); x.line(to: NSPoint(x: c.x + 110 * s, y: c.y + 110 * s))
        x.move(to: NSPoint(x: c.x - 110 * s, y: c.y + 110 * s)); x.line(to: NSPoint(x: c.x + 110 * s, y: c.y - 110 * s))
        shadowed(20, 0.4 * xA) { hotRed.withAlphaComponent(xA).setStroke(); x.stroke() }
    }

    // Scene 3 — Tidy arrives and sweeps the junk.
    let arrive = easeOutBack(progress(t, 9.2, 10.2))
    let tidyA = min(progress(t, 9.2, 9.6), 1 - progress(t, 20.2, 20.8))
    let tidyPos = NSPoint(x: lerp(2100, tidyHome.x, arrive), y: lerp(1200, tidyHome.y, arrive) + CGFloat(sin(t * 2)) * 8)
    if tidyA > 0 {
        for k in 0..<6 {
            let lag = Double(k) * 0.07
            let a = easeOutBack(progress(t - lag, 9.2, 10.2))
            let sp = NSPoint(x: lerp(2100, tidyHome.x, a) + 40, y: lerp(1200, tidyHome.y, a) + 30)
            sparkle(sp, CGFloat(26 - k * 3), rgb(0xFFFFFF, 0.8 * tidyA * (1 - Double(k) / 6)))
        }
        drawTidyIcon(at: tidyPos, size: 190, alpha: tidyA)
        for k in 0..<3 {
            let ang = t * 1.6 + Double(k) * 2.1
            sparkle(NSPoint(x: tidyPos.x + CGFloat(cos(ang)) * 140, y: tidyPos.y + CGFloat(sin(ang)) * 90), 14, rgb(0xFFFFFF, 0.8 * tidyA))
        }
    }
    for (i, item) in junk.enumerated() {
        let appear = easeOutBack(progress(t, 9.8 + Double(i) * 0.2, 10.4 + Double(i) * 0.2))
        let suck = ease(progress(t, 11.0 + Double(i) * 0.7, 11.8 + Double(i) * 0.7))
        let pos = NSPoint(x: lerp(item.1.x, tidyPos.x, suck), y: lerp(item.1.y, tidyPos.y, suck) + CGFloat(sin(t * 3 + Double(i))) * 5 * CGFloat(1 - suck))
        drawJunkBubble(item.0, at: pos, scale: CGFloat(appear) * CGFloat(1 - 0.9 * suck), alpha: min(appear, 1 - progress(suck, 0.85, 1)))
    }
    // "Photos kept" chip.
    let keptA = window(t, 13.8, 20.5)
    if keptA > 0 {
        let r = NSRect(x: laptopC.x - 180, y: 110, width: 360, height: 64)
        shadowed(16, 0.3 * keptA) { rgb(0x0F766E, 0.95 * keptA).setFill(); NSBezierPath(roundedRect: r, xRadius: 32, yRadius: 32).fill() }
        text("✓  Photos & videos kept", at: NSPoint(x: r.midX, y: r.midY), size: 28, weight: .bold, alpha: keptA)
    }

    NSGraphicsContext.restoreGraphicsState()

    // Captions.
    let caps: [(String, Double, Double)] = [("Storage almost full…", 0.3, 5.0), ("Don't delete your memories.", 5.2, 9.2),
                                             ("Tidy clears the junk you'll never miss.", 9.4, 15.0), ("Space back. Memories kept.", 15.2, 21.0)]
    for (s, a, b) in caps {
        let al = window(t, a, b)
        text(s, at: NSPoint(x: W / 2, y: H - 110 + CGFloat(1 - al) * 16), size: 76, weight: .heavy, alpha: al)
    }

    // Scene 5 — end card.
    let endA = ease(progress(t, 20.8, 21.8))
    if endA > 0 {
        NSGradient(starting: rgb(0x1B1240, endA), ending: rgb(0x0A2A2D, endA))!.draw(in: NSRect(x: 0, y: 0, width: W, height: H), angle: -60)
        NSGradient(colors: [violet.withAlphaComponent(0.4 * endA), violet.withAlphaComponent(0)])!
            .draw(fromCenter: NSPoint(x: 500, y: 900), radius: 0, toCenter: NSPoint(x: 500, y: 900), radius: 900, options: [])
        NSGradient(colors: [teal.withAlphaComponent(0.3 * endA), teal.withAlphaComponent(0)])!
            .draw(fromCenter: NSPoint(x: 1500, y: 150), radius: 0, toCenter: NSPoint(x: 1500, y: 150), radius: 900, options: [])
        let pop = CGFloat(easeOutBack(progress(t, 21.0, 21.9)))
        drawTidyIcon(at: NSPoint(x: W / 2, y: 660), size: 300 * pop, alpha: endA)
        let tA = progress(t, 21.6, 22.3)
        text("Tidy", at: NSPoint(x: W / 2, y: 420), size: 110, weight: .heavy, alpha: tA)
        text("Mac Storage Cleaner", at: NSPoint(x: W / 2, y: 330), size: 48, weight: .semibold, color: rgb(0xFFFFFF, 0.8), alpha: tA)
        let bA = progress(t, 22.3, 23.0)
        let pill = NSRect(x: W / 2 - 330, y: 190, width: 660, height: 80)
        rgb(0xFFFFFF, 0.12 * bA).setFill(); NSBezierPath(roundedRect: pill, xRadius: 40, yRadius: 40).fill()
        text("Available on the Mac App Store", at: NSPoint(x: pill.midX, y: pill.midY), size: 36, weight: .bold, alpha: bA)
        text("prateekrathore.com/tidy", at: NSPoint(x: W / 2, y: 120), size: 30, weight: .medium, color: rgb(0xFFFFFF, 0.6), alpha: bA)
    }
}

// MARK: - Encode

let url = outDir.appendingPathComponent("Tidy-Story.mp4")
try? FileManager.default.removeItem(at: url)
let writer = try! AVAssetWriter(outputURL: url, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(W), AVVideoHeightKey: Int(H),
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 12_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                                      AVVideoExpectedSourceFrameRateKey: Int(fps), AVVideoMaxKeyFrameIntervalKey: Int(fps)],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(W), kCVPixelBufferHeightKey as String: Int(H),
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let frames = Int(duration * Double(fps))
for i in 0..<frames {
    while !input.isReadyForMoreMediaData { usleep(2000) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    guard let buffer = pb else { fatalError("no pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: Int(W), height: Int(H), bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    drawFrame(Double(i) / Double(fps))
    NSGraphicsContext.restoreGraphicsState()
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
    if CommandLine.arguments.contains("--stills"), [60, 200, 330, 420, 520, 700].contains(i) {
        let img = ctx.makeImage()!
        try! NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!
            .write(to: outDir.appendingPathComponent("still-\(i).png"))
    }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print(writer.status == .completed ? "wrote \(url.path)" : "failed: \(String(describing: writer.error))")
