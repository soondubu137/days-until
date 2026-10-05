import SwiftUI
import WidgetKit

/// The countdown on the desktop, Small, Medium and Large. A glance first: a click anywhere opens the
/// popover under the menu bar item, as a click on the item does.
@main
struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "Countdown", provider: CountdownProvider()) { entry in
            CountdownWidgetView(entry: entry)
                // macOS draws the widget's shape, its background and the one-colour desktop look.
                .containerBackground(.fill.tertiary, for: .widget)
                .widgetURL(WidgetShare.url)
        }
        .configurationDisplayName(Text("Countdown", comment: "The desktop widget's name in the widget gallery."))
        .description(Text("The days left, at a glance.", comment: "The desktop widget's description in the widget gallery."))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

nonisolated struct CountdownEntry: TimelineEntry {
    let date: Date
    /// Nil while no countdown is set.
    let countdown: Countdown?
}

/// Reads the countdown the app shares, and lays out a timeline from when the widget next looks
/// different. The app reloads it when the countdown changes, and on clock and time zone changes.
nonisolated struct CountdownProvider: TimelineProvider {
    /// Instants per timeline: two months of midnights, or nearly three days of the final week's hours.
    private static let entryLimit = 64

    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: .now, countdown: Self.savedCountdown())
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(CountdownEntry(date: .now, countdown: Self.savedCountdown()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        // The extension can outlive a time zone change.
        NSTimeZone.resetSystemTimeZone()
        let now = Date()
        guard let countdown = Self.savedCountdown() else {
            completion(Timeline(entries: [CountdownEntry(date: now, countdown: nil)], policy: .never))
            return
        }
        let dates = CountdownMath.widgetUpdates(moment: countdown.targetDate, now: now, calendar: .local, limit: Self.entryLimit)
        let entries = ([now] + dates).map { CountdownEntry(date: $0, countdown: countdown) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func savedCountdown() -> Countdown? {
        // Another process writes the domain, so read what's there now, not what was read before.
        CFPreferencesAppSynchronize(WidgetShare.suiteName as CFString)
        let data = UserDefaults(suiteName: WidgetShare.suiteName)?.data(forKey: WidgetShare.countdownKey)
        return data.flatMap { try? JSONDecoder().decode(Countdown.self, from: $0) }
    }
}
