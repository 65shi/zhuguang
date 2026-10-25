import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: swift generate-icon.swift /path/to/Zhuguang.iconset\n", stderr)
    exit(2)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func drawIcon(pixels: Int) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "ZhuguangIcon", code: 1)
    }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    defer { NSGraphicsContext.restoreGraphicsState() }
    let cg = context.cgContext
    let scale = CGFloat(pixels) / 1024
    cg.scaleBy(x: scale, y: scale)
    cg.setShouldAntialias(true)

    let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 190, yRadius: 190)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 34
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    NSColor(calibratedRed: 0.12, green: 0.13, blue: 0.18, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.17, alpha: 1),
               ending: NSColor(calibratedRed: 0.30, green: 0.18, blue: 0.12, alpha: 1))!
        .draw(in: NSRect(x: 96, y: 96, width: 832, height: 832), angle: -90)

    let glow = NSGradient(colors: [
        NSColor(calibratedRed: 1, green: 0.56, blue: 0.15, alpha: 0.35),
        NSColor(calibratedRed: 1, green: 0.56, blue: 0.15, alpha: 0)
    ])!
    glow.draw(fromCenter: NSPoint(x: 512, y: 530), radius: 20,
              toCenter: NSPoint(x: 512, y: 530), radius: 390, options: .drawsBeforeStartingLocation)

    let center = NSPoint(x: 512, y: 540)
    let rays = NSBezierPath()
    rays.lineWidth = 27
    rays.lineCapStyle = .round
    for index in 0..<8 {
        let angle = CGFloat(index) * .pi / 4
        rays.move(to: NSPoint(x: center.x + cos(angle) * 206, y: center.y + sin(angle) * 206))
        rays.line(to: NSPoint(x: center.x + cos(angle) * 276, y: center.y + sin(angle) * 276))
    }
    NSColor(calibratedRed: 1, green: 0.75, blue: 0.32, alpha: 1).setStroke()
    rays.stroke()

    let sun = NSBezierPath(ovalIn: NSRect(x: 368, y: 396, width: 288, height: 288))
    NSGradient(starting: NSColor(calibratedRed: 1, green: 0.95, blue: 0.72, alpha: 1),
               ending: NSColor(calibratedRed: 1, green: 0.63, blue: 0.22, alpha: 1))!
        .draw(in: sun, angle: -90)

    // A quiet highlight gives the small menu utility a distinct, warm identity.
    let highlight = NSBezierPath()
    highlight.lineWidth = 11
    highlight.lineCapStyle = .round
    highlight.appendArc(withCenter: center, radius: 112, startAngle: 58, endAngle: 135)
    NSColor.white.withAlphaComponent(0.55).setStroke()
    highlight.stroke()
    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "ZhuguangIcon", code: 2)
    }
    return png
}

for size in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: size).write(to: outputURL.appendingPathComponent("icon_\(size)x\(size).png"))
    try drawIcon(pixels: size * 2).write(to: outputURL.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
