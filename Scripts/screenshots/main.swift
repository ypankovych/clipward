// Renders README screenshots of the real UI with demo data, without touching the
// clipboard or showing anything on screen: windows are placed off-screen and only
// the app's own windows are captured. Run via Scripts/screenshots.sh.
import AppKit
import ClipwardCore

final class DemoLoginItem: LoginItemService {
    var isEnabled: Bool { true }
    func setEnabled(_ enabled: Bool) throws {}
}

final class DemoShortcuts: ShortcutRegistering {
    var shortcut: HotKeyShortcut { .defaultShortcut }
    func change(to shortcut: HotKeyShortcut) -> Bool { true }
    func setSuspended(_ suspended: Bool) {}
}

let output = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/screenshots")
let offscreen = NSPoint(x: -6000, y: -6000)

func demoSettings() -> AppSettings {
    AppSettings(defaults: UserDefaults(suiteName: "clipward-screenshots-\(UUID().uuidString)")!,
                notificationCenter: NotificationCenter())
}

func text(_ string: String, extra: [ClipRepresentation] = []) -> ClipPayload {
    ClipPayload(items: [[ClipRepresentation(type: PasteboardTypes.plainText, data: Data(string.utf8))] + extra])
}

func demoImage() -> Data {
    let width = 1600, height = 1000
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let colors = [CGColor(red: 1.0, green: 0.62, blue: 0.35, alpha: 1), CGColor(red: 0.85, green: 0.28, blue: 0.55, alpha: 1)]
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
    context.setFillColor(CGColor(red: 1, green: 0.93, blue: 0.75, alpha: 0.95))
    context.fillEllipse(in: CGRect(x: 1050, y: 560, width: 300, height: 300))
    context.setFillColor(CGColor(red: 0.25, green: 0.12, blue: 0.35, alpha: 0.85))
    context.move(to: CGPoint(x: 0, y: 0))
    context.addLine(to: CGPoint(x: 520, y: 520))
    context.addLine(to: CGPoint(x: 900, y: 260))
    context.addLine(to: CGPoint(x: 1250, y: 600))
    context.addLine(to: CGPoint(x: 1600, y: 300))
    context.addLine(to: CGPoint(x: 1600, y: 0))
    context.fillPath()
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

func fileURL(_ name: String, directory: Bool = false) -> ClipPayload {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("clipward-demo").appendingPathComponent(name)
    if directory {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } else {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: url.path, contents: Data())
    }
    return ClipPayload(items: [[ClipRepresentation(type: PasteboardTypes.fileURL, data: Data(url.absoluteString.utf8))]])
}

func demoStore() -> HistoryStore {
    let store = HistoryStore(repository: InMemoryHistoryRepository(), maxItems: 200, retention: nil,
                             notificationCenter: NotificationCenter())
    let color = try! NSKeyedArchiver.archivedData(withRootObject: NSColor(srgbRed: 0.369, green: 0.361, blue: 0.902, alpha: 1),
                                                  requiringSecureCoding: false)
    let rtf = Data("{\\rtf1 Meeting notes}".utf8)
    // Oldest first; each `add` goes to the top.
    let entries: [(ClipPayload, String, TimeInterval)] = [
        (fileURL("Brand Assets", directory: true), "Finder", 2 * 86_400),
        (text("1 Infinite Loop, Cupertino, CA 95014"), "Maps", 26 * 3_600),
        (text("SELECT id, email FROM users WHERE created_at > now() - interval '7 days';"), "TablePlus", 5 * 3_600),
        (text("Meeting notes: hiring plan, Q3 budget, offsite dates", extra: [ClipRepresentation(type: PasteboardTypes.rtf, data: rtf)]), "Notes", 3 * 3_600),
        (ClipPayload(items: [[ClipRepresentation(type: PasteboardTypes.color, data: color)]]), "Digital Color Meter", 2 * 3_600),
        (fileURL("Quarterly Report.pdf"), "Finder", 3_700),
        (text("func greet(_ name: String) -> String { \"Hello, \\(name)!\" }"), "Xcode", 25 * 60),
        (ClipPayload(items: [[ClipRepresentation(type: PasteboardTypes.png, data: demoImage())]]), "Preview", 9 * 60),
        (text("https://github.com/ypankovych/clipward"), "Safari", 2 * 60 + 5),
        (text("Let's ship 1.0 on Thursday once QA signs off ✅"), "Slack", 10),
    ]
    let analyzer = ClipAnalyzer()
    for (payload, app, age) in entries {
        let metadata = analyzer.metadata(for: payload, source: ClipSource(name: app, bundleID: nil),
                                         date: Date().addingTimeInterval(-age))
        store.add(metadata, payload: payload)
    }
    return store
}

func pump(_ seconds: TimeInterval) {
    RunLoop.main.run(until: Date().addingTimeInterval(seconds))
}

func capture(_ window: NSWindow) -> CGImage {
    CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming, .bestResolution])!
}

/// Places a window image on a soft wallpaper-like gradient with a drop shadow.
func compose(_ image: CGImage, dark: Bool, padding: Int = 140) -> Data {
    let width = image.width + padding * 2, height = image.height + padding * 2
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let colors = dark
        ? [CGColor(red: 0.10, green: 0.11, blue: 0.26, alpha: 1), CGColor(red: 0.29, green: 0.16, blue: 0.42, alpha: 1)]
        : [CGColor(red: 0.62, green: 0.78, blue: 1.0, alpha: 1), CGColor(red: 0.86, green: 0.76, blue: 1.0, alpha: 1)]
    let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
    context.setShadow(offset: CGSize(width: 0, height: -24), blur: 70, color: CGColor(gray: 0, alpha: dark ? 0.6 : 0.35))
    context.draw(image, in: CGRect(x: padding, y: padding, width: image.width, height: image.height))
    return NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!
}

func save(_ data: Data, _ name: String) {
    let url = output.appendingPathComponent(name)
    try! data.write(to: url)
    print("wrote \(url.path)")
}

func render() {
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let store = demoStore()
    for (appearance, suffix) in [(NSAppearance.Name.darkAqua, "dark"), (.aqua, "light")] {
        NSApp.appearance = NSAppearance(named: appearance)

        let settings = demoSettings()
        let panel = HistoryPanel(size: HistoryViewController.preferredSize)
        let history = HistoryViewController(store: store, settings: settings)
        panel.contentViewController = history
        panel.setContentSize(HistoryViewController.preferredSize)
        panel.setFrameOrigin(offscreen)
        panel.orderFront(nil)
        history.prepareForDisplay()
        pump(0.8)
        save(compose(capture(panel), dark: suffix == "dark"), "history-\(suffix).png")
        panel.orderOut(nil)

        let settingsController = SettingsWindowController(settings: settings, loginItem: DemoLoginItem(),
                                                          shortcuts: DemoShortcuts(), onClearHistory: {})
        let window = settingsController.window!
        window.setFrameOrigin(offscreen)
        window.orderFront(nil)
        pump(0.8)
        save(compose(capture(window), dark: suffix == "dark"), "settings-\(suffix).png")
        window.orderOut(nil)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
DispatchQueue.main.async {
    render()
    exit(0)
}
app.run()
