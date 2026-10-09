import Foundation
import ServiceManagement

/// Starts the app when the user logs in.
protocol LoginItemService {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

enum LoginItem {
    /// The best mechanism for the running macOS version.
    static func makeService() -> LoginItemService {
        if #available(macOS 13, *) { return AppServiceLoginItem() }
        return LaunchAgentLoginItem()
    }
}

/// macOS 13+: registers the app itself via `SMAppService`; it shows up in
/// System Settings › General › Login Items.
@available(macOS 13, *)
final class AppServiceLoginItem: LoginItemService {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
            if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// macOS 10.13–12: a per-user launch agent that runs the app at login.
/// Works without a helper app or the deprecated shared-file-list API.
final class LaunchAgentLoginItem: LoginItemService {
    private let fileManager = FileManager.default

    private var label: String { (Bundle.main.bundleIdentifier ?? "io.github.ypankovych.Clipward") + ".login" }

    private var plistURL: URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(label + ".plist")
    }

    var isEnabled: Bool { fileManager.fileExists(atPath: plistURL.path) }

    func setEnabled(_ enabled: Bool) throws {
        guard enabled else {
            if isEnabled { try fileManager.removeItem(at: plistURL) }
            return
        }
        let job: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/usr/bin/open", "-a", Bundle.main.bundlePath],
            "RunAtLoad": true,
            "ProcessType": "Interactive",
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: job, format: .xml, options: 0)
        try fileManager.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
    }
}
