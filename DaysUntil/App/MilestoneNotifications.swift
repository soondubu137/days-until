import AppKit
import Combine
import OSLog

/// A milestone as the app hands it to macOS.
nonisolated struct MilestoneNotice: Equatable, Sendable {
    var identifier: String
    var title: String
    var body: String
    var date: Date
}

/// A milestone in Notification Center: when macOS delivered it, and when it was due.
nonisolated struct DeliveredMilestone: Equatable, Sendable {
    var identifier: String
    var delivered: Date
    var due: Date
}

/// What the app needs from macOS's notifications. `SystemNotifications` is the real one.
@MainActor
protocol NotificationService: AnyObject {
    /// Whether macOS lets the app notify, or nil while it hasn't asked.
    func isAllowed() async -> Bool?
    /// macOS's own prompt, which it shows only once. Whether notifications are allowed after it.
    func requestPermission() async -> Bool
    func add(_ notices: [MilestoneNotice]) async
    func removePending(_ identifiers: [String])
    func delivered() async -> [DeliveredMilestone]
    func removeDelivered(_ identifiers: [String])
    /// Days Until's page in System Settings › Notifications.
    func openSettings()
}

/// Notify Me: a notification at 100, 30 and 7 days, the day before, and on the day. They're scheduled
/// with macOS up front, so they arrive whether or not the app is running, and replaced whenever the
/// countdown, the switch, the clock or the time zone changes. The switch is the app's. macOS's
/// permission is read fresh, and a switch that's on while macOS has notifications off shows a dash.
@MainActor
final class MilestoneNotifications: ObservableObject {
    /// What the item's tooltip and the form's checkbox say they mean.
    static var summary: String { String(localized: "At 100, 30 and 7 days, the day before, and on the day") }

    /// Whether macOS lets the app notify, as last read, or nil while it hasn't asked.
    @Published private(set) var isAllowed: Bool?

    private static let logger = Logger(subsystem: "com.yinfenglu.DaysUntil", category: "Milestones")
    private static let identifiers = CountdownMath.milestoneDays.map { identifier($0) }

    private let store: CountdownStore
    private let service: any NotificationService
    private let now: () -> Date
    /// The last update asked for. Each waits for the one before, so an older one can't schedule after a
    /// newer one has cleared.
    private var latest: Task<Void, Never>?
    private var subscriptions: Set<AnyCancellable> = []

    init(store: CountdownStore, service: any NotificationService, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.service = service
        self.now = now
        // Published before the change is made; each update reads the store once it runs.
        store.$countdown.dropFirst().map { _ in }
            .merge(with: store.$notifiesAtMilestones.dropFirst().map { _ in })
            .sink { [weak self] in self?.reschedule() }
            .store(in: &subscriptions)
        // macOS posts these from background queues, the day change from its midnight timer.
        NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                NSTimeZone.resetSystemTimeZone()
                self?.reschedule()
            }
            .store(in: &subscriptions)
        // A day change also catches a Mac that slept through 9:00 AM; see `withdrawLate()`.
        Publishers.MergeMany(
            NotificationCenter.default.publisher(for: .NSSystemClockDidChange),
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.reschedule() }
        .store(in: &subscriptions)
        reschedule()
    }

    /// The ••• menu's checkmark: a dash while the switch is on and macOS doesn't allow notifications.
    var state: NSControl.StateValue {
        guard store.notifiesAtMilestones else { return .off }
        return isAllowed == false ? .mixed : .on
    }

    /// Notify Me in the ••• menu. A dash turns it off.
    func toggle() {
        set(!store.notifiesAtMilestones)
    }

    /// Turning it on asks macOS the first time. Don't Allow at macOS's prompt is an answer, and turns it
    /// back off. After that macOS never asks again, so turning it on opens System Settings instead.
    func set(_ isOn: Bool) {
        store.notifiesAtMilestones = isOn
        guard isOn else { return }
        enqueue { [self] in
            switch await service.isAllowed() {
            case nil:
                isAllowed = await service.requestPermission()
                if isAllowed == false { store.notifiesAtMilestones = false }
            case false?:
                isAllowed = false
                service.openSettings()
            case true?:
                isAllowed = true
            }
            await update()
        }
    }

    /// Reads macOS's permission again, each time the popover opens or the app becomes active, and
    /// schedules what's ahead if that has changed, as after allowing notifications in System Settings.
    func refresh() {
        enqueue { [self] in
            let allowed = await service.isAllowed()
            guard allowed != isAllowed else { return }
            await update()
        }
    }

    func openSettings() {
        service.openSettings()
    }

    /// Once everything asked for so far is done. For the tests.
    func settle() async {
        while let task = latest {
            await task.value
            if latest == task { return }
        }
    }

    private func reschedule() {
        enqueue { [self] in await update() }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = latest
        latest = Task {
            await previous?.value
            await work()
        }
    }

    private func update() async {
        isAllowed = await service.isAllowed()
        service.removePending(Self.identifiers)
        await withdrawLate()
        guard store.notifiesAtMilestones, isAllowed == true, let countdown = store.countdown else { return }
        let notices = CountdownMath.milestones(of: countdown, now: now(), calendar: .local).map { milestone in
            MilestoneNotice(identifier: Self.identifier(milestone.days), title: countdown.name, body: milestone.body, date: milestone.date)
        }
        await service.add(notices)
        Self.logger.info("Scheduled \(notices.count) milestones")
    }

    /// A Mac that was asleep or off at 9:00 AM can be handed a milestone on a later day, when its number
    /// would be wrong, so it's taken back.
    private func withdrawLate() async {
        let late = await service.delivered().filter {
            CountdownMath.calendarDays(from: $0.due, to: $0.delivered, calendar: .local) != 0
        }
        guard !late.isEmpty else { return }
        service.removeDelivered(late.map(\.identifier))
        Self.logger.info("Withdrew \(late.count) late milestones")
    }

    private static func identifier(_ days: Int) -> String {
        "milestone.\(days)"
    }
}
