import OSLog
import ServiceManagement

enum LaunchAtLogin {
    private static let logger = Logger(subsystem: "com.yinfenglu.DaysUntil", category: "LaunchAtLogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Couldn't turn launch at login \(enabled ? "on" : "off"): \(error)")
        }
    }
}
