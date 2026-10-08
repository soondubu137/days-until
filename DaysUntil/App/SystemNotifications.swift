import AppKit
import OSLog
import UserNotifications

/// macOS's notifications, for `MilestoneNotifications`, and what a click on one does. Tests never make
/// one, since it would ask the person for permission.
final class SystemNotifications: NSObject, NotificationService, UNUserNotificationCenterDelegate {
    /// A click on a milestone opens the popover, as a click on the item does. Set once the status item
    /// exists; a click that launched the app waits for it.
    var onOpen: (() -> Void)? {
        didSet {
            guard let onOpen, opensWhenReady else { return }
            opensWhenReady = false
            onOpen()
        }
    }
    private var opensWhenReady = false

    nonisolated private static let logger = Logger(subsystem: "com.yinfenglu.DaysUntil", category: "Milestones")

    /// Made as the app starts launching, so a click that launches it reaches the delegate.
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func isAllowed() async -> Bool? {
        switch await Self.authorizationStatus() {
        case .notDetermined: nil
        case .denied: false
        default: true
        }
    }

    func requestPermission() async -> Bool {
        await Self.requestAuthorization()
    }

    func add(_ notices: [MilestoneNotice]) async {
        await Self.add(notices)
    }

    func removePending(_ identifiers: [String]) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func delivered() async -> [DeliveredMilestone] {
        await Self.deliveredMilestones()
    }

    func removeDelivered(_ identifiers: [String]) {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? ""
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func open() {
        if let onOpen { onOpen() } else { opensWhenReady = true }
    }

    // MARK: - The notification center, off the main actor

    @concurrent nonisolated private static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Alerts and sounds. No badges: the menu bar item already says how far there is to go.
    @concurrent nonisolated private static func requestAuthorization() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        } catch {
            logger.error("Couldn't ask for notifications: \(error)")
            return false
        }
    }

    /// Each at its date in the Mac's time zone, which follows the Mac when it travels. The app replaces
    /// them when the time zone changes.
    @concurrent nonisolated private static func add(_ notices: [MilestoneNotice]) async {
        let center = UNUserNotificationCenter.current()
        let calendar = Calendar.local
        for notice in notices {
            let content = UNMutableNotificationContent()
            content.title = notice.title
            content.body = notice.body
            content.sound = .default
            content.threadIdentifier = "milestones"
            content.userInfo = ["due": notice.date.timeIntervalSinceReferenceDate]
            let when = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: notice.date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: notice.identifier, content: content, trigger: trigger))
            } catch {
                logger.error("Couldn't schedule \(notice.identifier): \(error)")
            }
        }
    }

    @concurrent nonisolated private static func deliveredMilestones() async -> [DeliveredMilestone] {
        await UNUserNotificationCenter.current().deliveredNotifications().compactMap { notification in
            let request = notification.request
            guard request.identifier.hasPrefix("milestone."), let due = request.content.userInfo["due"] as? Double else { return nil }
            return DeliveredMilestone(identifier: request.identifier, delivered: notification.date, due: Date(timeIntervalSinceReferenceDate: due))
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Shown while the popover is open too.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in self.open() }
        }
        completionHandler()
    }
}
