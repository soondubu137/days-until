import Foundation
import WidgetKit

nonisolated struct CountdownEntry: TimelineEntry {
    let date: Date
    /// Nil while no countdown is set.
    let countdown: Countdown?
}

/// Reads the countdown the app shares, and lays out a timeline from when the widget next looks
/// different. The app reloads it when the countdown changes, and on clock and time zone changes.
nonisolated struct CountdownProvider: TimelineProvider {
    /// Instants per timeline: two months of midnights, or nearly three days of the final week's hours.
    static let entryLimit = 64

    /// Where the app shares the countdown, or other defaults in tests.
    var defaults = UserDefaults(suiteName: WidgetShare.suiteName)

    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: .now, countdown: savedCountdown())
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(CountdownEntry(date: .now, countdown: savedCountdown()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        // The extension can outlive a time zone change.
        NSTimeZone.resetSystemTimeZone()
        completion(timeline(now: Date()))
    }

    /// An entry now and at each instant the widget next looks different, then a fresh timeline.
    /// With no countdown, the empty widget until the app says otherwise.
    func timeline(now: Date) -> Timeline<CountdownEntry> {
        guard let countdown = savedCountdown() else {
            return Timeline(entries: [CountdownEntry(date: now, countdown: nil)], policy: .never)
        }
        let dates = CountdownMath.widgetUpdates(moment: countdown.targetDate, now: now, calendar: .local, limit: Self.entryLimit)
        return Timeline(entries: ([now] + dates).map { CountdownEntry(date: $0, countdown: countdown) }, policy: .atEnd)
    }

    func savedCountdown() -> Countdown? {
        // Another process writes the domain, so read what's there now, not what was read before.
        CFPreferencesAppSynchronize(WidgetShare.suiteName as CFString)
        let data = defaults?.data(forKey: WidgetShare.countdownKey)
        return data.flatMap { try? JSONDecoder().decode(Countdown.self, from: $0) }
    }
}
