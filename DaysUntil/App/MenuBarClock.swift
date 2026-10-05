import AppKit
import Combine

/// Keeps the menu bar text current without polling. After each update it schedules one timer for the
/// instant the text next changes, and it recomputes straight away when the Mac wakes or the clock,
/// time zone or day changes.
final class MenuBarClock: ObservableObject {
    /// Nil while no countdown is set.
    @Published private(set) var text: CountdownMath.MenuBarText?

    private let store: CountdownStore
    private var timer: Timer?
    private var subscriptions: Set<AnyCancellable> = []

    init(store: CountdownStore) {
        self.store = store

        // `@Published` emits before the property changes, so use the emitted values, not the store's.
        store.$countdown.combineLatest(store.$menuBarStyle)
            .sink { [weak self] countdown, style in self?.update(countdown, style) }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                NSTimeZone.resetSystemTimeZone()
                self?.refresh()
            }
            .store(in: &subscriptions)

        Publishers.MergeMany(
            NotificationCenter.default.publisher(for: .NSSystemClockDidChange),
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged),
            NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.refresh() }
        .store(in: &subscriptions)
    }

    private func refresh() {
        update(store.countdown, store.menuBarStyle)
    }

    private func update(_ countdown: Countdown?, _ style: MenuBarStyle) {
        timer?.invalidate()
        timer = nil
        guard let countdown else {
            text = nil
            return
        }
        let now = Date()
        let calendar = Calendar.local
        let moment = CountdownMath.moment(of: countdown, calendar: calendar)
        let display = CountdownMath.menuBarDisplay(moment: moment, style: style, now: now, calendar: calendar)
        if text != display.text {
            text = display.text
        }
        if let nextChange = display.nextChange {
            schedule(at: nextChange, now: now)
        }
    }

    private func schedule(at date: Date, now: Date) {
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        // A timer fires late within its tolerance, never early, so the new text is always due when it runs.
        timer.tolerance = min(max(date.timeIntervalSince(now) * 0.1, 0.02), 1)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}
