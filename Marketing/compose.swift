// Composes App Store screenshots (2880×1800) from the raw window captures
// in Marketing/raw (made by `Tidy --render-screenshots`).
//
//   swift Marketing/compose.swift
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Marketing")
let raw = root.appendingPathComponent("raw")
let out = root.appendingPathComponent("AppStore")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let canvas = CGSize(width: 2880, height: 1800)

struct Shot {
    let file: String
    let headline: String
    let subhead: String
    let window: String
    var windowScale: CGFloat = 2.0
    var menuBar: String? = nil
}

// Order and captions come from ASO research on Mac storage apps: reviewers
// praise seeing where space went and quick, big wins, and complain about
// deleting the wrong thing, subscriptions and permission hassles. So the
// first three shots cover the win, the map and trust; developer features
// come last. Captions avoid Apple trademarks as product-like terms (App
// Review 5.2.5) and sample data uses fictional apps.
let shots = [
    Shot(file: "01-get-space-back", headline: "Get gigabytes back in minutes",
         subhead: "Tidy shows what's filling your disk and clears the junk safely.",
         window: "Overview-dark", menuBar: "MenuBar-dark"),
    Shot(file: "02-disk-map", headline: "See where your space went",
         subhead: "Every folder drawn to scale, with what's safe to clean inside it.",
         window: "DiskMap-dark", windowScale: 1.85),
    Shot(file: "03-know-whats-safe", headline: "Know it's safe before you delete",
         subhead: "Every item is labelled Safe or Review and explained in plain words.",
         window: "AppCaches-light"),
    Shot(file: "04-large-files", headline: "Find the big files you forgot",
         subhead: "Old videos, disk images and downloads, sorted by size and last opened.",
         window: "LargeFiles-dark"),
    Shot(file: "05-uninstall-apps", headline: "Remove apps completely",
         subhead: "Uninstall an app along with the settings and caches it leaves behind.",
         window: "Apps-light"),
    Shot(file: "06-photos-stay-put", headline: "Your photos stay put",
         subhead: "Tidy never deletes your personal files. Removals go to the Trash first.",
         window: "System-dark"),
    Shot(file: "07-old-installers", headline: "Clear old installers and leftovers",
         subhead: "Spot installers you've already used and data from apps you deleted.",
         window: "Installers-light"),
    Shot(file: "08-on-autopilot", headline: "Stays tidy on its own",
         subhead: "Schedule automatic cleaning of safe items: daily, weekly or monthly.",
         window: "Settings-dark"),
    Shot(file: "09-developers", headline: "Built for developers too",
         subhead: "Xcode, Android emulators, simulators and package caches, cleared safely.",
         window: "Xcode-dark", windowScale: 1.78),
    Shot(file: "10-private", headline: "No subscription. No account. No tracking.",
         subhead: "Lives in your menu bar, and everything it finds stays on your computer.",
         window: "Overview-light", menuBar: "MenuBar-light"),
]

let violet = NSColor(srgbRed: 0x8B / 255, green: 0x5C / 255, blue: 0xF6 / 255, alpha: 1)
let teal = NSColor(srgbRed: 0x14 / 255, green: 0xB8 / 255, blue: 0xA6 / 255, alpha: 1)

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    guard let rounded = base.fontDescriptor.withDesign(.rounded) else { return base }
    return NSFont(descriptor: rounded, size: size) ?? base
}

func drawCentered(_ text: String, font: NSFont, color: NSColor, y: CGFloat, maxWidth: CGFloat) {
    let para = NSMutableParagraphStyle()
    para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: para]
    let str = NSAttributedString(string: text, attributes: attrs)
    let bounds = str.boundingRect(with: NSSize(width: maxWidth, height: 1000), options: [.usesLineFragmentOrigin])
    str.draw(with: NSRect(x: (canvas.width - maxWidth) / 2, y: y - bounds.height, width: maxWidth, height: bounds.height),
             options: [.usesLineFragmentOrigin])
}

func drawImage(_ image: NSImage, in rect: NSRect, shadowRadius: CGFloat, cornerRadius: CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.5)
    shadow.shadowBlurRadius = shadowRadius
    shadow.shadowOffset = NSSize(width: 0, height: -shadowRadius * 0.35)
    shadow.set()
    NSColor.black.setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: 4, dy: 4), xRadius: cornerRadius, yRadius: cornerRadius).fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
}

for shot in shots {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas.width), pixelsHigh: Int(canvas.height),
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let full = NSRect(origin: .zero, size: canvas)

    // Background: deep brand gradient with two soft colour glows.
    NSGradient(colors: [NSColor(srgbRed: 0.09, green: 0.06, blue: 0.20, alpha: 1),
                        NSColor(srgbRed: 0.03, green: 0.14, blue: 0.16, alpha: 1)])!.draw(in: full, angle: -35)
    NSGradient(colors: [violet.withAlphaComponent(0.55), violet.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 420, y: 1650), radius: 0, toCenter: NSPoint(x: 420, y: 1650), radius: 1300, options: [])
    NSGradient(colors: [teal.withAlphaComponent(0.40), teal.withAlphaComponent(0)])!
        .draw(fromCenter: NSPoint(x: 2600, y: 150), radius: 0, toCenter: NSPoint(x: 2600, y: 150), radius: 1300, options: [])

    drawCentered(shot.headline, font: roundedFont(118, .bold), color: .white, y: canvas.height - 120, maxWidth: 2600)
    drawCentered(shot.subhead, font: roundedFont(52, .medium), color: NSColor.white.withAlphaComponent(0.78),
                 y: canvas.height - 290, maxWidth: 2400)

    if let window = NSImage(contentsOf: raw.appendingPathComponent("\(shot.window).png")) {
        let px = window.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? window.size
        let size = CGSize(width: px.width * shot.windowScale, height: px.height * shot.windowScale)
        let top = canvas.height - 440
        let rect = NSRect(x: (canvas.width - size.width) / 2, y: top - size.height, width: size.width, height: size.height)
        drawImage(window, in: rect, shadowRadius: 60, cornerRadius: 26 * shot.windowScale)

        if let menuName = shot.menuBar, let menu = NSImage(contentsOf: raw.appendingPathComponent("\(menuName).png")) {
            let mpx = menu.representations.first.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? menu.size
            let mRect = NSRect(x: rect.maxX - mpx.width * 0.62, y: rect.minY + 70, width: mpx.width, height: mpx.height)
            drawImage(menu, in: mRect, shadowRadius: 50, cornerRadius: 24)
        }
    }

    NSGraphicsContext.restoreGraphicsState()
    let url = out.appendingPathComponent("\(shot.file).png")
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote", url.path)
}
