import Foundation
import Testing
@testable import DaysUntil

/// Shares one defaults domain, cleared before and after each test, so runs don't pile up files.
@Suite(.serialized) @MainActor
final class StoreTests {
    let suite = "DaysUntilTests"
    let defaults: UserDefaults

    init() {
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }

    @Test func startsEmpty() {
        let store = CountdownStore(defaults: defaults)
        #expect(store.countdown == nil)
        #expect(store.menuBarStyle == .adaptive)
    }

    @Test func persistsAcrossLaunches() {
        let countdown = Countdown(
            name: "Wedding", icon: .emoji("💍"),
            date: CalendarDay(year: 2027, month: 6, day: 12), time: TimeOfDay(hour: 15, minute: 30),
            place: Place(timeZoneID: "Asia/Shanghai", name: "Home"),
            countingFrom: CalendarDay(year: 2026, month: 9, day: 29)
        )
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        store.menuBarStyle = .daysAndHours

        let relaunched = CountdownStore(defaults: defaults)
        #expect(relaunched.countdown == countdown)
        #expect(relaunched.menuBarStyle == .daysAndHours)
    }

    @Test func iconIsStoredReadably() throws {
        let symbol = try JSONEncoder().encode(CountdownIcon.symbol("house"))
        let emoji = try JSONEncoder().encode(CountdownIcon.emoji("🎄"))
        #expect(String(decoding: symbol, as: UTF8.self) == #"{"symbol":"house"}"#)
        #expect(try JSONDecoder().decode(CountdownIcon.self, from: emoji) == .emoji("🎄"))
    }
}
