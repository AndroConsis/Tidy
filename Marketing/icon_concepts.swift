// Renders Tidy's icon concepts. Concept A ("storage ring") is the shipped icon.
//   swiftc -o /tmp/icons Marketing/icon_concepts.swift && /tmp/icons <output dir>

import AppKit
let violet = NSColor(srgbRed: 0x8B/255, green: 0x5C/255, blue: 0xF6/255, alpha: 1)
let teal = NSColor(srgbRed: 0x14/255, green: 0xB8/255, blue: 0xA6/255, alpha: 1)
let amber = NSColor(srgbRed: 0xF5/255, green: 0x9E/255, blue: 0x0B/255, alpha: 1)
let coral = NSColor(srgbRed: 0xFB/255, green: 0x71/255, blue: 0x85/255, alpha: 1)
let ink = NSColor(srgbRed: 0.10, green: 0.07, blue: 0.22, alpha: 1)
let body = NSRect(x: 100, y: 100, width: 824, height: 824)

func sparkle(center c: NSPoint, radius r: CGFloat, waist: CGFloat = 0.16) -> NSBezierPath {
    // Four-pointed star with concave sides, like the SF "sparkle".
    let p = NSBezierPath()
    let pts = [NSPoint(x: c.x, y: c.y + r), NSPoint(x: c.x + r, y: c.y), NSPoint(x: c.x, y: c.y - r), NSPoint(x: c.x - r, y: c.y)]
    p.move(to: pts[0])
    for i in 0..<4 {
        let a = pts[i], b = pts[(i + 1) % 4]
        p.curve(to: b, controlPoint1: NSPoint(x: c.x + (a.x - c.x) * waist, y: c.y + (a.y - c.y) * waist),
                controlPoint2: NSPoint(x: c.x + (b.x - c.x) * waist, y: c.y + (b.y - c.y) * waist))
    }
    p.close()
    return p
}

func base(_ draw: () -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let shape = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.3); sh.shadowBlurRadius = 26; sh.shadowOffset = NSSize(width: 0, height: -12)
    NSGraphicsContext.saveGraphicsState(); sh.set(); NSColor.black.setFill(); shape.fill(); NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState(); shape.addClip()
    draw()
    // soft top highlight
    NSGradient(starting: NSColor.white.withAlphaComponent(0.16), ending: NSColor.white.withAlphaComponent(0))!.draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.14).setStroke(); shape.lineWidth = 3; shape.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func withShadow(_ blur: CGFloat, _ alpha: CGFloat, _ dy: CGFloat, _ f: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let s = NSShadow(); s.shadowColor = NSColor.black.withAlphaComponent(alpha); s.shadowBlurRadius = blur; s.shadowOffset = NSSize(width: 0, height: dy); s.set()
    f(); NSGraphicsContext.restoreGraphicsState()
}

// A — Storage ring: the app's storage bar as a gauge, mostly "free" teal with a warm reclaimable arc, sparkle at the centre.
let a = base {
    NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.10, blue: 0.34, alpha: 1), ink])!.draw(in: body, angle: -90)
    let c = NSPoint(x: 512, y: 512), r: CGFloat = 250, w: CGFloat = 92
    let track = NSBezierPath(); track.appendArc(withCenter: c, radius: r, startAngle: 0, endAngle: 360); track.lineWidth = w
    NSColor.white.withAlphaComponent(0.08).setStroke(); track.stroke()
    func arc(_ from: CGFloat, _ to: CGFloat, _ col: NSColor) {
        let p = NSBezierPath(); p.appendArc(withCenter: c, radius: r, startAngle: from, endAngle: to, clockwise: true)
        p.lineWidth = w; p.lineCapStyle = .round; col.setStroke(); p.stroke()
    }
    withShadow(20, 0.35, -6) {
        arc(72, -140, teal)            // free space, clockwise
        arc(-176, -250, NSColor(srgbRed: 0.98, green: 0.55, blue: 0.30, alpha: 1)) // reclaimable (warm)
    }
    withShadow(18, 0.25, -6) { NSColor.white.setFill(); sparkle(center: c, radius: 128).fill() }
    NSColor.white.withAlphaComponent(0.9).setFill(); sparkle(center: NSPoint(x: 612, y: 606), radius: 34).fill()
}

// B — Tidy stack: three storage "blocks"; the top one is being swept clean into sparkles.
let b = base {
    NSGradient(starting: violet, ending: teal)!.draw(in: body, angle: -50)
    let bars: [(CGFloat, CGFloat, CGFloat)] = [(300, 560, 1.0), (300, 440, 1.0), (300, 320, 0.62)]
    withShadow(22, 0.28, -8) {
        for (i, (x, y, frac)) in bars.enumerated() {
            let rect = NSRect(x: x, y: y, width: 424 * frac, height: 92)
            let p = NSBezierPath(roundedRect: rect, xRadius: 46, yRadius: 46)
            NSColor.white.withAlphaComponent(i == 2 ? 1 : 0.9 - CGFloat(i) * 0.12).setFill(); p.fill()
            if i < 2 {
                NSColor(srgbRed: 0.20, green: 0.12, blue: 0.40, alpha: 0.18).setFill()
                NSBezierPath(ovalIn: NSRect(x: x + 334, y: y + 30, width: 32, height: 32)).fill()
            }
        }
    }
    withShadow(14, 0.2, -4) {
        NSColor.white.setFill()
        sparkle(center: NSPoint(x: 640, y: 366), radius: 70).fill()
        sparkle(center: NSPoint(x: 718, y: 300), radius: 32).fill()
    }
}

// C — Clean sweep: a bold sparkle leaving a gradient swoosh, on a deep background (most minimal, reads well at 16px).
let cImg = base {
    NSGradient(colors: [NSColor(srgbRed: 0.13, green: 0.09, blue: 0.30, alpha: 1), NSColor(srgbRed: 0.04, green: 0.16, blue: 0.19, alpha: 1)])!.draw(in: body, angle: -60)
    let swoosh = NSBezierPath()
    swoosh.move(to: NSPoint(x: 230, y: 330))
    swoosh.curve(to: NSPoint(x: 600, y: 560), controlPoint1: NSPoint(x: 330, y: 300), controlPoint2: NSPoint(x: 470, y: 380))
    swoosh.lineWidth = 86; swoosh.lineCapStyle = .round
    NSGraphicsContext.saveGraphicsState()
    let outline = swoosh.cgPath.copy(strokingWithWidth: 86, lineCap: .round, lineJoin: .round, miterLimit: 10)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.addPath(outline); ctx.clip()
    NSGradient(colors: [teal.withAlphaComponent(0.0), teal, violet])!.draw(in: NSRect(x: 180, y: 250, width: 480, height: 360), angle: 20)
    NSGraphicsContext.restoreGraphicsState()
    withShadow(26, 0.35, -8) {
        NSGradient(starting: .white, ending: NSColor(srgbRed: 0.90, green: 0.88, blue: 1, alpha: 1))!.draw(in: sparkle(center: NSPoint(x: 612, y: 590), radius: 210), angle: -90)
    }
    NSColor.white.withAlphaComponent(0.85).setFill()
    sparkle(center: NSPoint(x: 360, y: 700), radius: 46).fill()
    sparkle(center: NSPoint(x: 780, y: 330), radius: 30).fill()
}

for (name, rep) in [("A-storage-ring", a), ("B-tidy-stack", b), ("C-clean-sweep", cImg)] {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/\(name).png"))
}
