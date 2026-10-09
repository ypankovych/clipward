// Draws the app icon and writes Resources/AppIcon.icns.
// Usage: swiftc Scripts/make-icon.swift -o /tmp/make-icon && /tmp/make-icon <repo root>
import AppKit

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func drawIcon(pixels: Int) -> Data {
    let size = CGFloat(pixels)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let unit = size / 1024

    // Background tile: macOS icon grid (824pt tile inside 1024 canvas), soft blue gradient.
    let tile = NSRect(x: 100 * unit, y: 100 * unit, width: 824 * unit, height: 824 * unit)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * unit, yRadius: 185 * unit)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = 20 * unit
    shadow.shadowOffset = NSSize(width: 0, height: -8 * unit)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor.white.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(calibratedRed: 0.33, green: 0.62, blue: 1.0, alpha: 1),
               ending: NSColor(calibratedRed: 0.20, green: 0.33, blue: 0.92, alpha: 1))!.draw(in: tilePath, angle: -90)

    // Clipboard board.
    let board = NSRect(x: 292 * unit, y: 220 * unit, width: 440 * unit, height: 560 * unit)
    NSColor.white.withAlphaComponent(0.96).setFill()
    NSBezierPath(roundedRect: board, xRadius: 56 * unit, yRadius: 56 * unit).fill()

    // Clip.
    let clip = NSRect(x: 402 * unit, y: 730 * unit, width: 220 * unit, height: 100 * unit)
    NSColor(calibratedRed: 0.14, green: 0.24, blue: 0.70, alpha: 1).setFill()
    NSBezierPath(roundedRect: clip, xRadius: 36 * unit, yRadius: 36 * unit).fill()

    // Text lines.
    NSColor(calibratedRed: 0.20, green: 0.33, blue: 0.92, alpha: 0.35).setFill()
    for (index, width) in [300.0, 250.0, 280.0].enumerated() {
        let y = (610 - Double(index) * 80) * Double(unit)
        NSBezierPath(roundedRect: NSRect(x: 362 * unit, y: CGFloat(y), width: CGFloat(width) * unit, height: 34 * unit),
                     xRadius: 17 * unit, yRadius: 17 * unit).fill()
    }

    // Lock badge.
    let lockColor = NSColor(calibratedRed: 0.14, green: 0.24, blue: 0.70, alpha: 1)
    let shackle = NSBezierPath()
    shackle.appendArc(withCenter: NSPoint(x: 512 * unit, y: 345 * unit), radius: 52 * unit, startAngle: 0, endAngle: 180)
    shackle.lineWidth = 26 * unit
    lockColor.setStroke()
    shackle.stroke()
    lockColor.setFill()
    NSBezierPath(roundedRect: NSRect(x: 432 * unit, y: 250 * unit, width: 160 * unit, height: 110 * unit),
                 xRadius: 24 * unit, yRadius: 24 * unit).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    try drawIcon(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try drawIcon(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}
let iconutil = Process()
iconutil.launchPath = "/usr/bin/iconutil"
iconutil.arguments = ["-c", "icns", iconset.path, "-o", root.appendingPathComponent("Resources/AppIcon.icns").path]
iconutil.launch()
iconutil.waitUntilExit()
exit(iconutil.terminationStatus)
