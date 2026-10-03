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
    /// The request macOS refused or didn't confirm, true to turn on, until it's resolved.
    @Published private(set) var failedRequest: Bool?
    /// macOS's reason for the refusal, kept for the tooltip rather than shown.
    @Published private(set) var failureReason: String?

    init(service: any LaunchAtLoginService = MainAppLoginService()) {
        self.service = service
        status = service.status
    }

    func refresh() {
        let current = service.status
        // A change made in System Settings supersedes an earlier failed request.
        if current != status {
            failedRequest = nil
            failureReason = nil
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
        failedRequest = nil
        failureReason = nil
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
                recordFailure(enabled: enabled, reason: String(localized: "macOS didn't confirm the change."))
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
        failureReason = reason
    }

    func retry() {
        guard let enabled = failedRequest else { return }
        set(enabled)
    }

    func openSettings() { service.openSettings() }
}
