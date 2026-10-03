import Combine
import OSLog
import ServiceManagement

@MainActor
protocol LaunchAtLoginService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSettings()
}

private struct MainAppLoginService: LaunchAtLoginService {
    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// System status is authoritative; a failed request never changes the checkmark optimistically.
@MainActor
final class LaunchAtLogin: ObservableObject {
    private static let logger = Logger(subsystem: "com.yinfenglu.DaysUntil", category: "LaunchAtLogin")
    private let service: any LaunchAtLoginService
    @Published private(set) var status: SMAppService.Status
    @Published private(set) var failure: String?
    private var failedRequest: Bool?

    init(service: any LaunchAtLoginService = MainAppLoginService()) {
        self.service = service
        status = service.status
    }

    var statusTitle: String {
        switch status {
        case .enabled: String(localized: "Launch at Login: Enabled")
        case .notRegistered: String(localized: "Launch at Login: Off")
        case .requiresApproval: String(localized: "Launch at Login: Approval Required")
        case .notFound: String(localized: "Launch at Login: Unavailable")
        @unknown default: String(localized: "Launch at Login: Unknown Status")
        }
    }

    var guidance: String? {
        switch status {
        case .enabled, .notRegistered: nil
        case .requiresApproval:
            String(localized: "Allow Days Until in System Settings → General → Login Items to launch at login.")
        case .notFound:
            String(localized: "macOS couldn't find the login item. Move Days Until to Applications and reopen it, then try again.")
        @unknown default:
            String(localized: "macOS returned an unknown login item status. Check Login Items in System Settings.")
        }
    }

    func refresh() {
        let current = service.status
        // A change made in System Settings supersedes an earlier failed request.
        if current != status {
            failure = nil
            failedRequest = nil
        }
        status = current
    }

    func toggle() {
        refresh()
        // Pending approval is already registered and must be cancellable.
        set(!(status == .enabled || status == .requiresApproval))
    }

    func set(_ enabled: Bool) {
        refresh()
        failure = nil
        failedRequest = nil
        if enabled && (status == .enabled || status == .requiresApproval) { return }
        if !enabled && status == .notRegistered { return }

        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            status = service.status
            let achieved = enabled ? (status == .enabled || status == .requiresApproval) : status == .notRegistered
            if !achieved {
                recordFailure(enabled: enabled, reason: String(localized: "macOS did not confirm the requested change. Check Login Items in System Settings, or try again."))
            }
        } catch {
            status = service.status
            let reason = (error as NSError).localizedDescription
            recordFailure(enabled: enabled, reason: reason)
            Self.logger.error("Couldn't turn launch at login \(enabled ? "on" : "off"): \(error)")
        }
    }

    private func recordFailure(enabled: Bool, reason: String) {
        failedRequest = enabled
        let title = enabled ? String(localized: "Couldn't enable launch at login.") : String(localized: "Couldn't disable launch at login.")
        failure = "\(title) \(reason)"
    }

    func retry() {
        guard let enabled = failedRequest else { return }
        set(enabled)
    }

    func openSettings() { service.openSettings() }
}
