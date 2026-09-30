import Foundation
import Testing
@testable import HomeTimer

private let losAngeles = "America/Los_Angeles"
private let tokyo = Place(timeZoneID: "Asia/Tokyo", name: "Tokyo")

private func calendar(_ zone: String) -> Calendar {
    CountdownMath.gregorian(in: TimeZone(identifier: zone)!)
}

/// A wall-clock time in `zone`.
private func date(_ zone: String, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    calendar(zone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

private func utc(_ iso: String) -> Date {
    try! Date(iso, strategy: .iso8601)
}

private func countdown(_ year: Int, _ month: Int, _ day: Int, at time: TimeOfDay? = nil, place: Place? = nil) -> Countdown {
    Countdown(
        name: "Going home", icon: .default,
        date: CalendarDay(year: year, month: month, day: day), time: time, place: place,
        countingFrom: CalendarDay(year: 2026, month: 9, day: 1)
    )
}

private func duration(days: Double = 0, hours: Double = 0, minutes: Double = 0, seconds: Double = 0) -> TimeInterval {
    ((days * 24 + hours) * 60 + minutes) * 60 + seconds
}

// MARK: -

struct DayCountingTests {
    let la = calendar(losAngeles)

    @Test func daysChangeAtLocalMidnight() {
        let moment = date(losAngeles, 2026, 12, 19)
        #expect(CountdownMath.calendarDays(from: date(losAngeles, 2026, 12, 17, 23, 59, 59), to: moment, calendar: la) == 2)
        #expect(CountdownMath.calendarDays(from: date(losAngeles, 2026, 12, 18), to: moment, calendar: la) == 1)
        #expect(CountdownMath.calendarDays(from: date(losAngeles, 2026, 12, 18, 23, 59, 59), to: moment, calendar: la) == 1)
    }

    @Test func daysEqualNightsLeftEvenWithUnderADayToGo() {
        let moment = date(losAngeles, 2026, 12, 19, 18, 40)
        #expect(CountdownMath.calendarDays(from: date(losAngeles, 2026, 12, 18, 22), to: moment, calendar: la) == 1)
        #expect(CountdownMath.calendarDays(from: date(losAngeles, 2026, 12, 19), to: moment, calendar: la) == 0)
    }

    @Test func daysAreCountedOnTheMacsClock() {
        // Midnight Dec 19 in Tokyo is 7 AM Dec 18 in Los Angeles.
        let moment = CountdownMath.moment(of: countdown(2026, 12, 19, place: tokyo), calendar: la)
        let now = utc("2026-12-18T10:00:00Z")
        #expect(CountdownMath.calendarDays(from: now, to: moment, calendar: la) == 0)
        #expect(CountdownMath.calendarDays(from: now, to: moment, calendar: calendar("Asia/Tokyo")) == 1)
    }
}

struct DaylightSavingTests {
    let la = calendar(losAngeles)

    @Test func springForwardLeavesAnHourLess() {
        let now = date(losAngeles, 2026, 3, 7, 12)
        let moment = CountdownMath.moment(of: countdown(2026, 3, 9, at: TimeOfDay(hour: 12, minute: 0)), calendar: la)
        #expect(moment.timeIntervalSince(now) == duration(hours: 47))
        #expect(CountdownMath.calendarDays(from: now, to: moment, calendar: la) == 2)
        #expect(CountdownMath.exactRemainingText(moment.timeIntervalSince(now + 0.5)) == "1d 22h 59m 59s")
    }

    @Test func fallBackLeavesAnHourMore() {
        let now = date(losAngeles, 2026, 10, 31, 12)
        let moment = CountdownMath.moment(of: countdown(2026, 11, 2, at: TimeOfDay(hour: 12, minute: 0)), calendar: la)
        #expect(moment.timeIntervalSince(now) == duration(hours: 49))
        #expect(CountdownMath.calendarDays(from: now, to: moment, calendar: la) == 2)
        let display = CountdownMath.menuBarDisplay(moment: moment, style: .adaptive, now: now + 1, calendar: la)
        #expect(display.text == .remaining("2d 0h"))
    }

    @Test func timeSkippedBySpringForwardResolvesAfterTheJump() {
        let moment = CountdownMath.moment(of: countdown(2026, 3, 8, at: TimeOfDay(hour: 2, minute: 30)), calendar: la)
        #expect(moment == utc("2026-03-08T10:30:00Z"))  // 3:30 AM PDT
    }

    @Test func dateOnlyWhereMidnightIsSkipped() {
        // Chile springs forward from midnight to 1 AM.
        let moment = CountdownMath.moment(of: countdown(2026, 9, 6), calendar: calendar("America/Santiago"))
        #expect(moment == utc("2026-09-06T04:00:00Z"))  // 1 AM, UTC−3
    }
}

struct FloatingAndPinnedTests {
    let evening = TimeOfDay(hour: 18, minute: 40)

    @Test func floatingMomentMovesWithTheMac() {
        let floating = countdown(2026, 12, 19, at: evening)
        #expect(CountdownMath.moment(of: floating, calendar: calendar(losAngeles)) == utc("2026-12-20T02:40:00Z"))
        #expect(CountdownMath.moment(of: floating, calendar: calendar("America/New_York")) == utc("2026-12-19T23:40:00Z"))
    }

    @Test func pinnedMomentStaysPut() {
        let pinned = countdown(2026, 12, 19, at: evening, place: tokyo)
        #expect(CountdownMath.moment(of: pinned, calendar: calendar(losAngeles)) == utc("2026-12-19T09:40:00Z"))
        #expect(CountdownMath.moment(of: pinned, calendar: calendar("America/New_York")) == utc("2026-12-19T09:40:00Z"))
    }

    @Test func pinnedDateOnlyCanFallOnThePreviousLocalDay() {
        let la = calendar(losAngeles)
        let moment = CountdownMath.moment(of: countdown(2026, 12, 19, place: tokyo), calendar: la)
        #expect(moment == date(losAngeles, 2026, 12, 18, 7))
        // "The day" is the local date, so Today shows on Dec 18 here.
        let afternoon = date(losAngeles, 2026, 12, 18, 15)
        #expect(CountdownMath.phase(of: moment, now: afternoon, calendar: la) == .reached)
        #expect(CountdownMath.menuBarDisplay(moment: moment, style: .adaptive, now: afternoon, calendar: la).text == .today)
    }

    @Test func countingFromIsReadOnTheMacsClock() {
        let pinned = countdown(2026, 12, 19, place: tokyo)
        #expect(CountdownMath.start(of: pinned, calendar: calendar(losAngeles)) == date(losAngeles, 2026, 9, 1))
    }
}

struct DateOnlyAndTimedTests {
    let la = calendar(losAngeles)

    @Test func dateOnlyRunsToTheStartOfTheDay() {
        #expect(CountdownMath.moment(of: countdown(2026, 12, 19), calendar: la) == date(losAngeles, 2026, 12, 19))
    }

    @Test func timedRunsToTheExactTime() {
        let timed = countdown(2026, 12, 19, at: TimeOfDay(hour: 18, minute: 40))
        #expect(CountdownMath.moment(of: timed, calendar: la) == date(losAngeles, 2026, 12, 19, 18, 40))
    }

    @Test func pickerDatesRoundTripThroughComponents() {
        let zone = TimeZone(identifier: losAngeles)!
        let picked = date(losAngeles, 2026, 12, 19, 18, 40)
        let day = CountdownMath.calendarDay(of: picked, in: zone)
        let time = CountdownMath.timeOfDay(of: picked, in: zone)
        #expect(day == CalendarDay(year: 2026, month: 12, day: 19))
        #expect(time == TimeOfDay(hour: 18, minute: 40))
        #expect(CountdownMath.date(day, at: time, in: zone) == picked)
    }
}

struct PastMomentTests {
    let la = calendar(losAngeles)
    let moment = date(losAngeles, 2026, 12, 19, 18, 40)

    @Test func reachedUntilTheDayEndsThenPast() {
        #expect(CountdownMath.phase(of: moment, now: moment - 1, calendar: la) == .counting)
        #expect(CountdownMath.phase(of: moment, now: moment, calendar: la) == .reached)
        #expect(CountdownMath.phase(of: moment, now: date(losAngeles, 2026, 12, 19, 23, 59, 59), calendar: la) == .reached)
        #expect(CountdownMath.phase(of: moment, now: date(losAngeles, 2026, 12, 20), calendar: la) == .past)
    }

    @Test func menuBarShowsTodayThenOnlyTheIcon() {
        let reached = CountdownMath.menuBarDisplay(moment: moment, style: .adaptive, now: moment, calendar: la)
        #expect(reached == .init(text: .today, nextChange: date(losAngeles, 2026, 12, 20)))
        let past = CountdownMath.menuBarDisplay(moment: moment, style: .adaptive, now: date(losAngeles, 2026, 12, 20), calendar: la)
        #expect(past == .init(text: .iconOnly, nextChange: nil))
    }

    @Test func daysSinceCountsMidnights() {
        #expect(CountdownMath.calendarDays(from: moment, to: date(losAngeles, 2026, 12, 19, 23), calendar: la) == 0)
        #expect(CountdownMath.calendarDays(from: moment, to: date(losAngeles, 2026, 12, 22, 9), calendar: la) == 3)
    }
}

struct MenuBarTextTests {
    let la = calendar(losAngeles)
    let moment = date(losAngeles, 2026, 12, 19, 18, 40)

    func text(_ style: MenuBarStyle = .adaptive, at now: Date) -> CountdownMath.MenuBarText {
        CountdownMath.menuBarDisplay(moment: moment, style: style, now: now, calendar: la).text
    }

    @Test func adaptiveAtEachThreshold() {
        #expect(text(at: date(losAngeles, 2026, 9, 29, 10, 41)) == .remaining("81d"))
        #expect(text(at: moment - CountdownMath.week - 1) == .remaining("7d"))
        #expect(text(at: moment - CountdownMath.week) == .remaining("6d 23h"))
        #expect(text(at: moment - duration(days: 6, hours: 14, minutes: 30)) == .remaining("6d 14h"))
        #expect(text(at: moment - CountdownMath.day - 1) == .remaining("1d 0h"))
        #expect(text(at: moment - CountdownMath.day) == .remaining("23:59:59"))
        #expect(text(at: moment - duration(hours: 13, minutes: 42, seconds: 7.5)) == .remaining("13:42:07"))
        #expect(text(at: moment - 0.5) == .remaining("00:00:00"))
        #expect(text(at: moment) == .today)
    }

    @Test func daysOnly() {
        #expect(text(.daysOnly, at: date(losAngeles, 2026, 9, 29, 10, 41)) == .remaining("81d"))
        #expect(text(.daysOnly, at: date(losAngeles, 2026, 12, 18, 23)) == .remaining("1d"))
        #expect(text(.daysOnly, at: date(losAngeles, 2026, 12, 19, 9)) == .today)
    }

    @Test func daysAndHours() {
        #expect(text(.daysAndHours, at: moment - duration(days: 81, hours: 8, minutes: 59)) == .remaining("81d 8h"))
        #expect(text(.daysAndHours, at: moment - duration(hours: 5, minutes: 30)) == .remaining("5h"))
        #expect(text(.daysAndHours, at: moment - duration(minutes: 30)) == .remaining("<1h"))
    }

    @Test func alwaysSeconds() {
        #expect(text(.alwaysSeconds, at: moment - duration(days: 80, hours: 7, minutes: 58, seconds: 13.5)) == .remaining("80d 07:58:13"))
        #expect(text(.alwaysSeconds, at: moment - 42.5) == .remaining("00:00:42"))
    }

    @Test func iconOnlyNeverChanges() {
        for now in [date(losAngeles, 2026, 9, 29), moment - 30, moment] {
            #expect(CountdownMath.menuBarDisplay(moment: moment, style: .iconOnly, now: now, calendar: la) == .init(text: .iconOnly, nextChange: nil))
        }
    }

    @Test func exactRemainingLine() {
        #expect(CountdownMath.exactRemainingText(duration(days: 80, hours: 7, minutes: 58, seconds: 13.5)) == "80d 07h 58m 13s")
        #expect(CountdownMath.exactRemainingText(duration(hours: 7, minutes: 5, seconds: 0.5)) == "07h 05m 00s")
    }
}

struct NextChangeTests {
    let la = calendar(losAngeles)
    let moment = date(losAngeles, 2026, 12, 19, 18, 40)

    func nextChange(_ style: MenuBarStyle = .adaptive, at now: Date) -> Date? {
        CountdownMath.menuBarDisplay(moment: moment, style: style, now: now, calendar: la).nextChange
    }

    @Test func daysChangeAtTheNextLocalMidnight() {
        #expect(nextChange(at: date(losAngeles, 2026, 9, 29, 10, 41)) == date(losAngeles, 2026, 9, 30))
        #expect(nextChange(.daysOnly, at: date(losAngeles, 2026, 12, 18, 23)) == date(losAngeles, 2026, 12, 19))
    }

    @Test func adaptiveDaysSwitchToHoursAWeekOut() {
        // The next midnight is later than the moment a week out, 6:40 PM.
        #expect(nextChange(at: date(losAngeles, 2026, 12, 12, 12)) == moment - CountdownMath.week)
    }

    @Test func hoursChangeOnWholeHoursBeforeTheMoment() {
        #expect(nextChange(at: moment - duration(days: 6, hours: 14, minutes: 30)) == moment - duration(days: 6, hours: 14))
        #expect(nextChange(.daysAndHours, at: moment - duration(minutes: 30)) == moment)
    }

    @Test func secondsChangeOnWholeSecondsBeforeTheMoment() {
        #expect(nextChange(at: moment - 100.25) == moment - 100)
        #expect(nextChange(at: moment - 0.5) == moment)
    }

    @Test func daysOnlyTodayLastsUntilTheDayEnds() {
        #expect(nextChange(.daysOnly, at: date(losAngeles, 2026, 12, 19, 9)) == date(losAngeles, 2026, 12, 20))
    }

    /// Walking from one next-change instant to the next, the text changes at every step and at no
    /// point in between. Each walk starts `lead` before the moment and covers at most 300 changes.
    @Test(arguments: [
        (MenuBarStyle.adaptive, duration(days: 7, hours: 3)),  // days, then hours
        (.adaptive, duration(days: 1, seconds: 5)),  // hours, then seconds
        (.adaptive, duration(seconds: 5)),  // the last seconds, Today, then the icon alone
        (.daysOnly, duration(days: 9, hours: 3)),
        (.daysAndHours, duration(days: 2, hours: 3)),
        (.alwaysSeconds, duration(minutes: 3)),
    ])
    func everyNextChangeIsARealChange(style: MenuBarStyle, lead: TimeInterval) {
        let maxSteps = 300
        var now = moment - lead - 0.4
        var display = CountdownMath.menuBarDisplay(moment: moment, style: style, now: now, calendar: la)
        var steps = 0
        while let next = display.nextChange, steps < maxSteps {
            #expect(next > now)
            let justBefore = CountdownMath.menuBarDisplay(moment: moment, style: style, now: next - 0.001, calendar: la)
            #expect(justBefore.text == display.text)
            let after = CountdownMath.menuBarDisplay(moment: moment, style: style, now: next, calendar: la)
            #expect(after.text != display.text)
            (now, display) = (next, after)
            steps += 1
        }
        #expect(steps == maxSteps || display == .init(text: .iconOnly, nextChange: nil))
    }
}

struct OtherUnitsTests {
    let la = calendar(losAngeles)
    let saturday = date(losAngeles, 2026, 12, 19)

    @Test func weekdaysBeforeTheDay() {
        // Monday to Friday, then the day itself.
        let units = CountdownMath.otherUnits(moment: saturday, now: date(losAngeles, 2026, 12, 14, 10), calendar: la)
        #expect(units.weekends == 0)
        #expect(units.workdays == 5)
    }

    @Test func todayCountsAndTheDayItselfDoesnt() {
        let units = CountdownMath.otherUnits(moment: saturday, now: date(losAngeles, 2026, 12, 12, 10), calendar: la)
        #expect(units.weekends == 1)
        #expect(units.workdays == 5)
    }

    @Test func longCountdown() {
        // Tue Sep 29 to Sat Dec 19: 81 days, 11 weeks and 4 days (Tue to Fri).
        let units = CountdownMath.otherUnits(moment: saturday, now: date(losAngeles, 2026, 9, 29, 10, 41), calendar: la)
        #expect(units.weekends == 11)
        #expect(units.workdays == 11 * 5 + 4)
    }

    @Test func weeksUseExactTime() {
        let units = CountdownMath.otherUnits(moment: saturday, now: saturday - duration(days: 10, hours: 12), calendar: la)
        #expect(units.weeks == 1.5)
    }

    @Test func progress() {
        let start = saturday - duration(days: 100)
        #expect(CountdownMath.progress(start: start, moment: saturday, now: saturday - duration(days: 25)) == 0.75)
        #expect(CountdownMath.progress(start: start, moment: saturday, now: start - 1) == 0)
        #expect(CountdownMath.progress(start: start, moment: saturday, now: saturday + 1) == 1)
        #expect(CountdownMath.progress(start: saturday, moment: saturday, now: saturday) == nil)
    }
}

struct PlaceTests {
    let now = utc("2026-09-29T17:41:00Z")
    let la = TimeZone(identifier: losAngeles)!

    @Test func offsets() {
        #expect(CountdownMath.offsetText(of: TimeZone(identifier: "Asia/Tokyo")!, from: la, at: now) == "16h ahead")
        #expect(CountdownMath.offsetText(of: la, from: TimeZone(identifier: "Asia/Tokyo")!, at: now) == "16h behind")
        #expect(CountdownMath.offsetText(of: TimeZone(identifier: "Asia/Kolkata")!, from: la, at: now) == "12h 30m ahead")
        #expect(CountdownMath.offsetText(of: TimeZone(identifier: "America/Vancouver")!, from: la, at: now) == "same time")
    }

    @Test func dayAndNight() {
        #expect(!CountdownMath.isDaytime(in: TimeZone(identifier: "Asia/Tokyo")!, at: now))  // 2:41 AM
        #expect(CountdownMath.isDaytime(in: la, at: now))  // 10:41 AM
    }

    @Test func yourTimeLineOnlyWhenOffsetsDiffer() {
        let shanghai = TimeZone(identifier: "Asia/Shanghai")!
        #expect(CountdownMath.sameOffset(shanghai, TimeZone(identifier: "Asia/Taipei")!, at: now))
        #expect(!CountdownMath.sameOffset(shanghai, la, at: now))
    }
}

struct ValidationTests {
    let la = calendar(losAngeles)
    let now = date(losAngeles, 2026, 9, 29, 10, 41)

    @Test func momentMustBeInTheFuture() {
        #expect(CountdownMath.validate(countdown(2026, 9, 29), now: now, calendar: la) == .momentNotInFuture)
        #expect(CountdownMath.validate(countdown(2026, 9, 29, at: TimeOfDay(hour: 10, minute: 41)), now: now, calendar: la) == .momentNotInFuture)
        #expect(CountdownMath.validate(countdown(2026, 9, 29, at: TimeOfDay(hour: 10, minute: 42)), now: now, calendar: la) == nil)
    }

    @Test func countingFromMustBeBeforeTheMoment() {
        var sameDay = countdown(2026, 12, 19)
        sameDay.countingFrom = CalendarDay(year: 2026, month: 12, day: 19)
        #expect(CountdownMath.validate(sameDay, now: now, calendar: la) == .startNotBeforeMoment)
        sameDay.time = TimeOfDay(hour: 18, minute: 40)
        #expect(CountdownMath.validate(sameDay, now: now, calendar: la) == nil)
    }
}
