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
        #expect(store.popoverBackground == .liquidGlass)
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
        store.popoverBackground = .solid

        let relaunched = CountdownStore(defaults: defaults)
        #expect(relaunched.countdown == countdown)
        #expect(relaunched.menuBarStyle == .daysAndHours)
        #expect(relaunched.popoverBackground == .solid)
    }

    @Test func celebratesEachMomentOnce() {
        var countdown = Countdown(
            name: "Going home", icon: .symbol("house"),
            date: CalendarDay(year: 2026, month: 12, day: 18), time: TimeOfDay(hour: 9, minute: 40),
            place: Place(timeZoneID: "Asia/Tokyo", name: "Tokyo"),
            countingFrom: CalendarDay(year: 2026, month: 8, day: 3)
        )
        let store = CountdownStore(defaults: defaults)
        #expect(!store.hasCelebrated(countdown))
        store.markCelebrated(countdown)
        #expect(CountdownStore(defaults: defaults).hasCelebrated(countdown))

        // A new name or icon is the same moment.
        countdown.name = "Home"
        countdown.icon = .emoji("🏠")
        #expect(store.hasCelebrated(countdown))

        // A new date, time or place is a new one.
        var later = countdown
        later.date.day = 19
        var earlier = countdown
        earlier.time = TimeOfDay(hour: 8, minute: 0)
        var elsewhere = countdown
        elsewhere.place = nil
        for moment in [later, earlier, elsewhere] {
            #expect(!store.hasCelebrated(moment))
        }
    }

    @Test func iconIsStoredReadably() throws {
        let symbol = try JSONEncoder().encode(CountdownIcon.symbol("house"))
        let emoji = try JSONEncoder().encode(CountdownIcon.emoji("🎄"))
        #expect(String(decoding: symbol, as: UTF8.self) == #"{"symbol":"house"}"#)
        #expect(try JSONDecoder().decode(CountdownIcon.self, from: emoji) == .emoji("🎄"))
    }
}
