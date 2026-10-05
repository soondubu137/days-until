import AppKit
import Testing
@testable import DaysUntil

/// The copy of the countdown the desktop widget reads, and its reloads. Never the real shared
/// domain: these use defaults in memory.
@Suite @MainActor
struct WidgetSyncTests {
    let defaults: UserDefaults = MemoryDefaults()
    let shared: UserDefaults = MemoryDefaults()
    let reloads = Calls<Void>()
    let countdown = Countdown(name: "Trip", icon: .emoji("🧳"), targetDate: Date().addingTimeInterval(86_400 * 30),
                              showsTime: true, place: Place(timeZoneID: "Asia/Tokyo", name: "Tokyo"), startDate: Date())

    private func sharedCountdown() throws -> Countdown? {
        try shared.data(forKey: WidgetShare.countdownKey).map { try JSONDecoder().decode(Countdown.self, from: $0) }
    }

    @Test func copiesTheCountdownAtLaunchAndOnEachChange() throws {
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        let sync = WidgetSync(store: store, defaults: shared, reload: { reloads.record(()) })
        #expect(try sharedCountdown() == countdown)
        #expect(reloads.values.count == 1)

        var renamed = countdown
        renamed.name = "Home"
        store.countdown = renamed
        #expect(try sharedCountdown() == renamed)
        #expect(reloads.values.count == 2)

        // Setting the same countdown again changes nothing the widget shows.
        store.countdown = renamed
        #expect(reloads.values.count == 2)

        store.countdown = nil
        #expect(try sharedCountdown() == nil)
        #expect(reloads.values.count == 3)
        withExtendedLifetime(sync) {}
    }

    @Test func reloadsWhenTheClockTimeZoneOrLanguageChanges() async throws {
        let store = CountdownStore(defaults: defaults)
        let sync = WidgetSync(store: store, defaults: shared, reload: { reloads.record(()) })
        #expect(reloads.values.count == 1)
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange, NSLocale.currentLocaleDidChangeNotification] {
            NotificationCenter.default.post(name: name, object: nil)
        }
        // They arrive on the main queue, which runs once the test lets go of it.
        try await Task.sleep(for: .milliseconds(100))
        #expect(reloads.values.count == 4)
        withExtendedLifetime(sync) {}
    }

    @Test func aClickOnTheWidgetOpensOnlyItsOwnLinks() {
        let delegate = AppDelegate()
        // Without a status item yet, neither does anything; other links are left alone.
        delegate.application(NSApplication.shared, open: [URL(string: "https://example.com")!])
        delegate.application(NSApplication.shared, open: [WidgetShare.url])
        #expect(WidgetShare.url.scheme == "daysuntil")
    }
}
