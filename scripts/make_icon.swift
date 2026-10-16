// Renders the TaskAlarm app icon (a happy alarm-clock smiley on a violet tile) into an .iconset folder.
// Usage: swift scripts/make_icon.swift <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px)
    // Flip to y-down so the face math matches the app.
    ctx.translateBy(x: 0, y: s)
    ctx.scaleBy(x: 1, y: -1)

    let space = CGColorSpace(name: CGColorSpace.sRGB)
    func grad(_ a: UInt32, _ b: UInt32, _ aa: CGFloat = 1, _ ba: CGFloat = 1) -> CGGradient {
        CGGradient(colorsSpace: space, colors: [color(a, aa), color(b, ba)] as CFArray, locations: [0, 1])!
    }

    // Squircle tile (macOS icon grid: ~80% of canvas) in deep brand violet.
    let inset = s * 0.1
    let tile = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: s * 0.012), blur: s * 0.03, color: color(0x000000, 0.3))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x5B3FD9))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    ctx.drawLinearGradient(grad(0x9378FF, 0x3A2499), start: CGPoint(x: tile.minX, y: tile.minY), end: CGPoint(x: tile.maxX, y: tile.maxY), options: [])
    // Pink glow in the top-right, like the brand backgrounds.
    let glowC = CGPoint(x: tile.maxX - tile.width * 0.1, y: tile.minY + tile.width * 0.1)
    ctx.drawRadialGradient(grad(0xFF8CB3, 0xFF8CB3, 0.45, 0), startCenter: glowC, startRadius: 0, endCenter: glowC, endRadius: tile.width * 0.6, options: [])
    ctx.restoreGState()

    // The smiley is an alarm clock: two amber bells and a hammer on top, little feet below.
    let d = tile.width * 0.62
    let face = CGRect(x: s / 2 - d / 2, y: s / 2 - d / 2 + tile.width * 0.05, width: d, height: d)
    let center = CGPoint(x: face.midX, y: face.midY)
    let ink = color(0x1C1430)

    // Feet
    ctx.setStrokeColor(color(0x1C1430, 0.85))
    ctx.setLineWidth(d * 0.07)
    ctx.setLineCap(.round)
    for side in [-1.0, 1.0] as [CGFloat] {
        ctx.move(to: CGPoint(x: center.x + side * d * 0.28, y: center.y + d * 0.42))
        ctx.addLine(to: CGPoint(x: center.x + side * d * 0.38, y: center.y + d * 0.56))
        ctx.strokePath()
    }

    // Bells (domes tilted outward) with a hammer between them
    ctx.setStrokeColor(ink)
    ctx.setLineWidth(d * 0.05)
    ctx.move(to: CGPoint(x: center.x, y: face.minY + d * 0.02))
    ctx.addLine(to: CGPoint(x: center.x, y: face.minY - d * 0.12))
    ctx.strokePath()
    ctx.setFillColor(ink)
    ctx.fillEllipse(in: CGRect(x: center.x - d * 0.05, y: face.minY - d * 0.17, width: d * 0.1, height: d * 0.1))
    for side in [-1.0, 1.0] as [CGFloat] {
        ctx.saveGState()
        ctx.translateBy(x: center.x + side * d * 0.33, y: face.minY + d * 0.04)
        ctx.rotate(by: side * 0.62)
        let r = d * 0.2
        let dome = CGMutablePath()
        dome.addArc(center: .zero, radius: r, startAngle: .pi, endAngle: 0, clockwise: false)
        dome.closeSubpath()
        ctx.addPath(dome)
        ctx.setShadow(offset: CGSize(width: 0, height: s * 0.006), blur: s * 0.012, color: color(0x000000, 0.25))
        ctx.setFillColor(color(0xFFB020))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        ctx.addPath(dome)
        ctx.clip()
        ctx.drawLinearGradient(grad(0xFFD36B, 0xF08C00), start: CGPoint(x: 0, y: -r), end: .zero, options: [])
        ctx.resetClip()
        ctx.setFillColor(color(0xFFE7A8))
        ctx.fillEllipse(in: CGRect(x: -r * 0.5, y: -r * 0.78, width: r * 0.42, height: r * 0.22))
        ctx.setFillColor(ink)
        ctx.fillEllipse(in: CGRect(x: -r * 0.12, y: -r * 1.2, width: r * 0.24, height: r * 0.24))
        ctx.restoreGState()
    }

    // Ringing lines
    ctx.setStrokeColor(color(0xFFFFFF, 0.85))
    ctx.setLineWidth(d * 0.035)
    for side in [-1.0, 1.0] as [CGFloat] {
        for (i, len) in [(0, 0.09), (1, 0.07)] as [(Int, CGFloat)] {
            let a = (side < 0 ? CGFloat.pi : 0) + side * (-0.18 - CGFloat(i) * 0.36)
            let r0 = d * 0.68
            let o = CGPoint(x: center.x, y: center.y - d * 0.04)
            ctx.move(to: CGPoint(x: o.x + cos(a) * r0, y: o.y + sin(a) * r0))
            ctx.addLine(to: CGPoint(x: o.x + cos(a) * (r0 + d * len), y: o.y + sin(a) * (r0 + d * len)))
            ctx.strokePath()
        }
    }

    // Face body: a soft lavender-white dial with a violet rim
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: s * 0.018), blur: s * 0.04, color: color(0x1C0F5C, 0.5))
    ctx.setFillColor(color(0x6A47F5))
    ctx.fillEllipse(in: face.insetBy(dx: -d * 0.045, dy: -d * 0.045))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: face)
    ctx.clip()
    ctx.drawLinearGradient(grad(0xFFFFFF, 0xE4DCFF), start: CGPoint(x: 0, y: face.minY), end: CGPoint(x: 0, y: face.maxY), options: [])
    ctx.restoreGState()

    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: face.minX + x * d, y: face.minY + y * d) }

    // Blush
    ctx.setFillColor(color(0xFF8CB3, 0.8))
    for x in [0.25, 0.75] as [CGFloat] {
        let c = p(x, 0.6)
        ctx.fillEllipse(in: CGRect(x: c.x - d * 0.08, y: c.y - d * 0.045, width: d * 0.16, height: d * 0.09))
    }

    // Eyes
    ctx.setFillColor(color(0x1C1430))
    for x in [0.355, 0.645] as [CGFloat] {
        let c = p(x, 0.41)
        ctx.fillEllipse(in: CGRect(x: c.x - d * 0.0575, y: c.y - d * 0.085, width: d * 0.115, height: d * 0.17))
        // Eye sparkle
        ctx.setFillColor(color(0xFFFFFF, 0.9))
        ctx.fillEllipse(in: CGRect(x: c.x - d * 0.012, y: c.y - d * 0.06, width: d * 0.035, height: d * 0.035))
        ctx.setFillColor(color(0x1C1430))
    }

    // Smile (open grin, same curves as the "happy/celebrating" mood)
    let base: CGFloat = 0.645 - 0.9 * 0.07
    let mouth = CGMutablePath()
    mouth.move(to: p(0.29, base))
    mouth.addQuadCurve(to: p(0.71, base), control: p(0.5, base + 0.22))
    mouth.addQuadCurve(to: p(0.29, base), control: p(0.5, base + 0.06))
    mouth.closeSubpath()
    ctx.addPath(mouth)
    ctx.setFillColor(color(0x1C1430))
    ctx.fillPath()
    ctx.addPath(mouth)
    ctx.setStrokeColor(color(0x1C1430))
    ctx.setLineWidth(d * 0.07)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.strokePath()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("Icon written to \(out.path)")
