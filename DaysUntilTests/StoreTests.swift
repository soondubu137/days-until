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
            targetDate: Date(timeIntervalSince1970: 1_813_000_000), showsTime: true,
            place: Place(timeZoneID: "Asia/Shanghai", name: "Home"),
            startDate: Date(timeIntervalSince1970: 1_790_000_000)
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

    @Test func iconIsStoredReadably() throws {
        let symbol = try JSONEncoder().encode(CountdownIcon.symbol("house"))
        let emoji = try JSONEncoder().encode(CountdownIcon.emoji("🎄"))
        #expect(String(decoding: symbol, as: UTF8.self) == #"{"symbol":"house"}"#)
        #expect(try JSONDecoder().decode(CountdownIcon.self, from: emoji) == .emoji("🎄"))
    }
    @Test func legacyPinnedTimesMigrateOnceAndKeepABackup() throws {
        let legacy = Data(#"{"name":"Trip","icon":{"symbol":"airplane"},"date":{"year":2027,"month":3,"day":14},"time":{"hour":2,"minute":30},"place":{"timeZoneID":"Europe/London","name":"London"},"countingFrom":{"year":2026,"month":10,"day":1}}"#.utf8)
        defaults.set(legacy, forKey: "countdown")
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let first = CountdownStore(defaults: defaults, migrationTimeZone: la)
        let saved = try #require(first.countdown)
        #expect(saved.targetDate == (try Date("2027-03-14T02:30:00Z", strategy: .iso8601)))
        #expect(saved.startDate == (try Date("2026-10-01T07:00:00Z", strategy: .iso8601)))
        #expect(defaults.data(forKey: "countdown.v1.backup") == legacy)
        let next = CountdownStore(defaults: defaults, migrationTimeZone: TimeZone(identifier: "Asia/Tokyo")!)
        #expect(next.countdown == saved)
        #expect(Draft(editing: saved, timeZone: la).countdown == saved)
    }

    @Test func legacyDateOnlyKeepsItsOriginalForeignMidnight() throws {
        let legacy = Data(#"{"name":"Trip","icon":{"symbol":"house"},"date":{"year":2026,"month":12,"day":19},"place":{"timeZoneID":"Asia/Tokyo","name":"Tokyo"},"countingFrom":{"year":2026,"month":10,"day":1}}"#.utf8)
        defaults.set(legacy, forKey: "countdown")
        let store = CountdownStore(defaults: defaults, migrationTimeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let saved = try #require(store.countdown)
        #expect(saved.targetDate == (try Date("2026-12-18T15:00:00Z", strategy: .iso8601)))
        #expect(!saved.showsTime)
        #expect(Draft(editing: saved, timeZone: TimeZone(identifier: "Europe/London")!).countdown == saved)
    }

    @Test func legacyFloatingDatesAreFrozenAtMigrationAndNeverResolvedAgain() throws {
        let legacy = Data(#"{"name":"Trip","icon":{"symbol":"house"},"date":{"year":2026,"month":12,"day":19},"countingFrom":{"year":2026,"month":10,"day":1}}"#.utf8)
        defaults.set(legacy, forKey: "countdown")
        let store = CountdownStore(defaults: defaults, migrationTimeZone: TimeZone(identifier: "America/Los_Angeles")!)
        let saved = try #require(store.countdown)
        #expect(saved.targetDate == (try Date("2026-12-19T08:00:00Z", strategy: .iso8601)))
        #expect(CountdownStore(defaults: defaults, migrationTimeZone: .gmt).countdown == saved)
    }

    @Test func unreadableDataIsNotOverwrittenByMigration() {
        let data = Data("invalid".utf8)
        defaults.set(data, forKey: "countdown")
        #expect(CountdownStore(defaults: defaults).countdown == nil)
        #expect(defaults.data(forKey: "countdown") == data)
        #expect(defaults.data(forKey: "countdown.v1.backup") == nil)
    }

}
