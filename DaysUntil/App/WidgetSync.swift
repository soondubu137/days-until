import Combine
import Foundation
import WidgetKit

/// Keeps the desktop widget current. It copies the countdown to where the widget can read it (see
/// `WidgetShare`), and has the widget's timeline laid out again when the countdown changes, and when
/// the clock, time zone or language does, which move the instants it was laid out for.
final class WidgetSync {
    private let defaults: UserDefaults?
    /// Has WidgetKit lay out the widget's timeline again.
    private let reload: () -> Void
    private var subscriptions: Set<AnyCancellable> = []

    init(
        store: CountdownStore,
        defaults: UserDefaults? = UserDefaults(suiteName: WidgetShare.suiteName),
        reload: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }
    ) {
        self.defaults = defaults
        self.reload = reload
        // `@Published` emits before the property changes, so use the emitted value. The first comes
        // at once, at launch.
        store.$countdown
            .removeDuplicates()
            .sink { [weak self] countdown in self?.share(countdown) }
            .store(in: &subscriptions)

        Publishers.MergeMany(
            NotificationCenter.default.publisher(for: .NSSystemClockDidChange),
            NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange),
            NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] _ in self?.reload() }
        .store(in: &subscriptions)
    }

    private func share(_ countdown: Countdown?) {
        if let countdown, let data = try? JSONEncoder().encode(countdown) {
            defaults?.set(data, forKey: WidgetShare.countdownKey)
        } else {
            defaults?.removeObject(forKey: WidgetShare.countdownKey)
        }
        reload()
    }
}
