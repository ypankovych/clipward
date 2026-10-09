// Draws the DMG window background (1x and 2x) with a "drag to Applications" arrow.
// Usage: swiftc make-background.swift -o bg && ./bg <output directory>
import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let size = NSSize(width: 640, height: 400)

func render(scale: CGFloat) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGradient(starting: NSColor(calibratedRed: 0.97, green: 0.97, blue: 1.0, alpha: 1),
               ending: NSColor(calibratedRed: 0.90, green: 0.92, blue: 0.99, alpha: 1))!
        .draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // Arrow between the app icon (x 170) and the Applications link (x 470), icon centre y = 200 from the top.
    let accent = NSColor(calibratedRed: 0.42, green: 0.56, blue: 0.97, alpha: 1)
    accent.setStroke()
    accent.setFill()
    let y = size.height - 200
    let shaft = NSBezierPath()
    shaft.move(to: NSPoint(x: 262, y: y))
    shaft.line(to: NSPoint(x: 366, y: y))
    shaft.lineWidth = 6
    shaft.lineCapStyle = .round
    shaft.stroke()
    let head = NSBezierPath()
    head.move(to: NSPoint(x: 382, y: y))
    head.line(to: NSPoint(x: 360, y: y + 16))
    head.line(to: NSPoint(x: 360, y: y - 16))
    head.close()
    head.fill()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let title: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1),
        .paragraphStyle: paragraph,
    ]
    let subtitle: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13),
        .foregroundColor: NSColor(calibratedWhite: 0.4, alpha: 1),
        .paragraphStyle: paragraph,
    ]
    NSAttributedString(string: "Install Clipward", attributes: title)
        .draw(in: NSRect(x: 0, y: size.height - 70, width: size.width, height: 30))
    NSAttributedString(string: "Drag Clipward into the Applications folder, then open it from there.", attributes: subtitle)
        .draw(in: NSRect(x: 0, y: 52, width: size.width, height: 20))
    NSAttributedString(string: "Open history with ⌥⌘C", attributes: subtitle)
        .draw(in: NSRect(x: 0, y: 32, width: size.width, height: 20))

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try! render(scale: 1).write(to: output.appendingPathComponent("background.png"))
try! render(scale: 2).write(to: output.appendingPathComponent("background@2x.png"))
