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
    var build = ExtensionBuild()

    func placeholder(in context: Context) -> CountdownEntry {
        quitIfReplaced()
        return CountdownEntry(date: .now, countdown: savedCountdown())
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        quitIfReplaced()
        completion(CountdownEntry(date: .now, countdown: savedCountdown()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        quitIfReplaced()
        // The extension can outlive a time zone change.
        NSTimeZone.resetSystemTimeZone()
        completion(timeline(now: Date()))
    }

    /// An update replaces the extension on disk but leaves this process running the old build, and
    /// macOS turns down everything it draws from then on ("Bundle version did not match"), leaving
    /// grey placeholders until the next login. Quitting lets macOS start the new build when it tries
    /// again, which it does at once.
    private func quitIfReplaced() {
        if build.isReplaced { exit(0) }
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

/// The extension's build when it started, and whether a different one has since been put where it
/// started from.
nonisolated struct ExtensionBuild {
    let launched: String?
    let bundleURL: URL

    /// Bundle reads its Info.plist once, on first use, so this is read when the widget starts, before
    /// an update can replace it.
    init(bundle: Bundle = .main) {
        launched = bundle.infoDictionary?[kCFBundleVersionKey as String] as? String
        bundleURL = bundle.bundleURL
    }

    /// Whether the extension on disk now has another build. Nothing there, mid-install, isn't.
    var isReplaced: Bool {
        let info = NSDictionary(contentsOf: bundleURL.appending(path: "Contents/Info.plist"))
        guard let launched, let onDisk = info?[kCFBundleVersionKey as String] as? String else { return false }
        return onDisk != launched
    }
}
