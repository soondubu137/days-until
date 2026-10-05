import Foundation
import Testing
@testable import DaysUntil

private func timestamp(_ value: String) -> Date { try! Date(value, strategy: .iso8601) }
private func zone(_ identifier: String) -> TimeZone { TimeZone(identifier: identifier)! }

@MainActor struct HiddenTimeTests {
    @Test func dateOnlyZoneChangesKeepInactiveClockFieldsAndBothInstants() throws {
        var draft = Draft(now: timestamp("2026-10-01T12:00:00Z"), timeZone: zone("America/Los_Angeles"))
        draft.name = "Trip"
        draft.dateInput.select(CalendarDay(year: 2027, month: 3, day: 14))
        draft.time = TimeOfDay(hour: 9, minute: 40)
        let saved = try #require(draft.countdown)
        for destination in ["Asia/Tokyo", "Pacific/Honolulu", "Europe/London", "America/Los_Angeles"] {
            draft.changeTimeZone(to: zone(destination))
            #expect(draft.time == TimeOfDay(hour: 9, minute: 40))
            #expect(draft.countdown?.targetDate == saved.targetDate)
            #expect(draft.countdown?.startDate == saved.startDate)
        }
        draft.hasTime = true
        #expect(draft.targetDate == timestamp("2027-03-14T16:40:00Z"))
    }

    @Test func reenabledHiddenTimeIsValidatedInTheLabelledZone() {
        var draft = Draft(now: timestamp("2026-10-01T12:00:00Z"), timeZone: zone("America/Los_Angeles"))
        draft.dateInput.select(CalendarDay(year: 2027, month: 3, day: 14))
        draft.time = TimeOfDay(hour: 2, minute: 30)
        let target = draft.targetDate
        draft.changeTimeZone(to: zone("America/Denver"))
        #expect(draft.targetDate == target)
        #expect(draft.time == TimeOfDay(hour: 2, minute: 30))
        draft.hasTime = true
        #expect(draft.targetDate == nil) // 02:30 is skipped in Denver on this date.
    }

    @Test func hiddenTimeDoesNotInventAChoiceForARepeatedHour() {
        var draft = Draft(now: timestamp("2026-10-01T12:00:00Z"), timeZone: zone("America/Phoenix"))
        draft.dateInput.select(CalendarDay(year: 2026, month: 11, day: 1))
        draft.time = TimeOfDay(hour: 1, minute: 30)
        draft.changeTimeZone(to: zone("America/Los_Angeles"))
        draft.hasTime = true
        #expect(draft.candidates.count == 2)
        #expect(draft.targetDate == nil)
    }

    @Test func hiddenRepeatedOccurrenceSurvivesARoundTrip() throws {
        let target = timestamp("2026-11-01T09:30:00Z")
        let saved = Countdown(name: "Trip", icon: .default, targetDate: target, showsTime: true,
                              place: nil, startDate: target - 86400)
        var draft = Draft(editing: saved, timeZone: zone("America/Los_Angeles"))
        draft.hasTime = false
        let dateOnlyTarget = try #require(draft.targetDate)
        draft.changeTimeZone(to: zone("Asia/Tokyo"))
        draft.changeTimeZone(to: zone("America/Los_Angeles"))
        #expect(draft.targetDate == dateOnlyTarget)
        draft.hasTime = true
        #expect(draft.targetDate == target)
    }
}

struct CivilDayRunwayTests {
    @Test(arguments: [
        ("America/Santiago", "2026-09-06T04:00:00Z"), // Skipped midnight, day starts at 01:00.
        ("Asia/Kathmandu", "1985-12-31T18:30:00Z"), // Day starts at 00:15 after an offset change.
        ("America/Havana", "2026-11-01T04:00:00Z"), // Midnight occurs twice, but one day begins.
    ])
    func marksTheActualDayStart(identifier: String, start: String) {
        let calendar = CountdownMath.gregorian(in: zone(identifier))
        let boundary = timestamp(start)
        let moment = boundary + 12 * 3600
        let runway = CountdownMath.runway(start: moment - 3 * 86400, moment: moment,
                                         now: boundary - 3600, calendar: calendar, maxTicks: 69)
        let marked = runway.ticks.filter(\.isMarked)
        #expect(marked.count == 1)
        #expect(marked.first?.position == 0.5)
        #expect(runway.labels.contains { $0.date == boundary })
    }

    @Test(arguments: [
        ("America/Los_Angeles", "2026-11-01T09:00:00Z"),
        ("Australia/Lord_Howe", "2027-04-03T15:00:00Z"),
        ("Australia/Lord_Howe", "2026-10-03T15:30:00Z"),
    ])
    func hourTicksMatchRealClockHoursAcrossTransitions(identifier: String, transition: String) {
        let calendar = CountdownMath.gregorian(in: zone(identifier))
        let moment = timestamp(transition) + 12 * 3600 + 123
        let start = moment - 86400
        let runway = CountdownMath.runway(start: moment - 3 * 86400, moment: moment,
                                         now: moment - 3600, calendar: calendar, maxTicks: 69)
        // Independent oracle: walk real elapsed minutes, retaining actual :00 clock readings.
        var minute = Date(timeIntervalSinceReferenceDate: (start.timeIntervalSinceReferenceDate / 60).rounded(.up) * 60)
        var expected: [Date] = []
        while minute < moment {
            if calendar.component(.minute, from: minute) == 0 { expected.append(minute) }
            minute += 60
        }
        #expect(runway.ticks.map { start + $0.position * 86400 } == expected)
    }
}

struct TimeZoneInvariantTests {
    @Test func everyKnownZoneResolvesInstantsAroundUpcomingTransitions() {
        let start = timestamp("2026-01-01T00:00:00Z")
        let end = timestamp("2031-01-01T00:00:00Z")
        var samples = 0
        for identifier in TimeZone.knownTimeZoneIdentifiers {
            let timeZone = zone(identifier)
            let calendar = CountdownMath.gregorian(in: timeZone)
            var cursor = start
            while let transition = timeZone.nextDaylightSavingTimeTransition(after: cursor), transition < end {
                for offset in [-7200.0, -3600, -1800, -60, 0, 60, 1800, 3600, 7200] {
                    let date = transition + offset
                    let day = CountdownMath.calendarDay(of: date, in: timeZone)
                    let time = CountdownMath.timeOfDay(of: date, in: timeZone)
                    let candidates = CountdownMath.possibleMoments(on: day, at: time, in: timeZone)
                    #expect(candidates.contains(date), "\(identifier) at \(date)")
                    #expect(Set(candidates).count == candidates.count)
                    let dayEnd = CountdownMath.endOfDay(containing: date, calendar: calendar)
                    #expect(dayEnd > date, "\(identifier) at \(date)")
                    let display = CountdownMath.menuBarDisplay(moment: date + 10 * 86400,
                                                              style: .daysOnly, now: date, calendar: calendar)
                    // The next local midnight, or sooner when the clocks went back in between and
                    // a whole day of real time runs out first.
                    #expect(display.nextChange.map { $0 > date && $0 <= dayEnd } == true, "\(identifier) at \(date)")
                    if let next = display.nextChange {
                        let after = CountdownMath.menuBarDisplay(moment: date + 10 * 86400, style: .daysOnly, now: next, calendar: calendar)
                        #expect(after.text != display.text, "\(identifier) at \(date)")
                    }
                    samples += 1
                }
                cursor = transition + 1
            }
        }
        #expect(samples > 10_000)
    }

    @Test @MainActor func editingAndPersistencePreserveSubsecondsInEveryKnownZone() throws {
        let target = timestamp("2027-01-01T00:00:00Z") + 0.375
        let start = timestamp("2026-01-01T00:00:00Z") + 0.125
        for showsTime in [false, true] {
            let saved = Countdown(name: "Trip", icon: .default, targetDate: target, showsTime: showsTime,
                                  place: nil, startDate: start)
            for identifier in TimeZone.knownTimeZoneIdentifiers {
                var draft = Draft(editing: saved, timeZone: zone(identifier))
                draft.name = "Renamed"
                let result = try #require(draft.countdown)
                let decoded = try JSONDecoder().decode(Countdown.self, from: JSONEncoder().encode(result))
                #expect(decoded.targetDate == target, "\(identifier)")
                #expect(decoded.startDate == start, "\(identifier)")
            }
        }
    }

    @Test func allDisplayStylesScheduleFutureChangesAcrossDSTAndYearBoundaries() throws {
        let targets = [timestamp("2026-11-01T09:30:00Z"), timestamp("2027-01-01T00:00:00Z"),
                       timestamp("2027-03-14T10:00:00Z"), timestamp("2027-04-03T15:15:00Z") + 0.375]
        for identifier in ["America/Los_Angeles", "America/Santiago", "Australia/Lord_Howe", "Asia/Kathmandu", "Pacific/Kiritimati"] {
            let calendar = CountdownMath.gregorian(in: zone(identifier))
            for target in targets {
                for style in MenuBarStyle.allCases where style != .iconOnly {
                    for lead in [604800.5, 86400.5, 3600.5, 1.5, 0.001] {
                        let now = target - lead
                        let display = CountdownMath.menuBarDisplay(moment: target, style: style, now: now, calendar: calendar)
                        let next = try #require(display.nextChange)
                        #expect(next > now)
                        let after = CountdownMath.menuBarDisplay(moment: target, style: style, now: next, calendar: calendar)
                        #expect(after.text != display.text)
                        #expect(after.nextChange == nil || after.nextChange! > next)
                    }
                }
            }
        }
    }
}
