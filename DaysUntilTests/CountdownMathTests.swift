import Foundation
import Testing
@testable import DaysUntil

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

private func countdown(_ year: Int, _ month: Int, _ day: Int, at time: TimeOfDay? = nil, place: Place? = nil, zone: String = losAngeles) -> Countdown {
    Countdown(
        name: "Going home", icon: .default,
        targetDate: date(zone, year, month, day, time?.hour ?? 0, time?.minute ?? 0),
        showsTime: time != nil, place: place,
        startDate: date(zone, 2026, 9, 1)
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
        let moment = CountdownMath.moment(of: countdown(2026, 12, 19, place: tokyo, zone: "Asia/Tokyo"), calendar: la)
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
        #expect(CountdownMath.exactRemainingText(moment.timeIntervalSince(now + 0.5)) == "1d 23h 00m 00s")
    }

    @Test func fallBackLeavesAnHourMore() {
        let now = date(losAngeles, 2026, 10, 31, 12)
        let moment = CountdownMath.moment(of: countdown(2026, 11, 2, at: TimeOfDay(hour: 12, minute: 0)), calendar: la)
        #expect(moment.timeIntervalSince(now) == duration(hours: 49))
        #expect(CountdownMath.calendarDays(from: now, to: moment, calendar: la) == 2)
        let display = CountdownMath.menuBarDisplay(moment: moment, style: .adaptive, now: now + 1, calendar: la)
        #expect(display.text == .remaining("2d 0h"))
    }

    @Test func timeSkippedBySpringForwardIsRejected() {
        #expect(CountdownMath.possibleMoments(on: CalendarDay(year: 2026, month: 3, day: 8),
                at: TimeOfDay(hour: 2, minute: 30), in: la.timeZone).isEmpty)
    }

    @Test func dateOnlyWhereMidnightIsSkipped() {
        // Chile springs forward from midnight to 1 AM.
        let moment = CountdownMath.moment(of: countdown(2026, 9, 6, zone: "America/Santiago"), calendar: calendar("America/Santiago"))
        #expect(moment == utc("2026-09-06T04:00:00Z"))  // 1 AM, UTC−3
    }
}

struct AbsoluteMomentTests {
    @Test func changingTheMacTimeZoneNeverMovesTheTargetOrStart() {
        for time in [nil, TimeOfDay(hour: 18, minute: 40)] {
            let saved = countdown(2026, 12, 19, at: time, place: tokyo)
            for zone in [losAngeles, "America/New_York", "Asia/Tokyo", "Pacific/Apia"] {
                #expect(CountdownMath.moment(of: saved, calendar: calendar(zone)) == saved.targetDate)
                #expect(CountdownMath.start(of: saved, calendar: calendar(zone)) == saved.startDate)
            }
        }
    }

    @Test func displayPlaceNeverDefinesTheInputTimeZone() {
        var saved = countdown(2026, 12, 19, at: TimeOfDay(hour: 18, minute: 40))
        let expected = utc("2026-12-20T02:40:00Z")
        #expect(saved.targetDate == expected)
        saved.place = tokyo
        #expect(CountdownMath.moment(of: saved, calendar: calendar(losAngeles)) == expected)
        saved.place = Place(timeZoneID: "Europe/London", name: "London")
        #expect(CountdownMath.moment(of: saved, calendar: calendar("Asia/Tokyo")) == expected)
    }

    @Test func dateOnlyStillUsesTheSameInstantWhenTravelling() {
        let saved = countdown(2026, 12, 19)
        let newYork = calendar("America/New_York")
        #expect(newYork.component(.hour, from: saved.targetDate) == 3)
        #expect(CountdownMath.phase(of: saved.targetDate, now: utc("2026-12-19T07:59:59Z"), calendar: newYork) == .counting)
        #expect(CountdownMath.phase(of: saved.targetDate, now: utc("2026-12-19T08:00:00Z"), calendar: newYork) == .reached)
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
        #expect(text(at: moment - CountdownMath.week) == .remaining("7d 0h"))
        #expect(text(at: moment - duration(days: 6, hours: 14, minutes: 30)) == .remaining("6d 14h"))
        #expect(text(at: moment - CountdownMath.day - 1) == .remaining("1d 0h"))
        #expect(text(at: moment - CountdownMath.day) == .remaining("24:00:00"))
        #expect(text(at: moment - duration(hours: 13, minutes: 42, seconds: 7.5)) == .remaining("13:42:08"))
        #expect(text(at: moment - 0.5) == .remaining("00:00:01"))
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
        #expect(text(.alwaysSeconds, at: moment - duration(days: 80, hours: 7, minutes: 58, seconds: 13.5)) == .remaining("80d 07:58:14"))
        #expect(text(.alwaysSeconds, at: moment - 42.5) == .remaining("00:00:43"))
    }

    @Test func iconOnlyNeverChanges() {
        for now in [date(losAngeles, 2026, 9, 29), moment - 30, moment] {
            #expect(CountdownMath.menuBarDisplay(moment: moment, style: .iconOnly, now: now, calendar: la) == .init(text: .iconOnly, nextChange: nil))
        }
    }

    @Test func exactRemainingLine() {
        #expect(CountdownMath.exactRemainingText(duration(days: 80, hours: 7, minutes: 58, seconds: 13.5)) == "80d 07h 58m 14s")
        #expect(CountdownMath.exactRemainingText(duration(hours: 7, minutes: 5, seconds: 0.5)) == "07h 05m 01s")
    }
}

struct ReadoutTests {
    let la = calendar(losAngeles)
    let moment = date(losAngeles, 2026, 12, 19, 18, 40)

    func readout(at now: Date) -> CountdownMath.Readout {
        CountdownMath.readout(moment: moment, now: now, calendar: la)
    }

    @Test func climbsTheSameLadderAsTheMenuBar() {
        #expect(readout(at: date(losAngeles, 2026, 9, 29, 10, 41)) == .days(81))
        #expect(readout(at: moment - CountdownMath.week - 1) == .days(7))
        #expect(readout(at: moment - CountdownMath.week) == .daysAndHours(days: 7, hours: 0))
        #expect(readout(at: moment - duration(days: 5, hours: 16, minutes: 58)) == .daysAndHours(days: 5, hours: 16))
        #expect(readout(at: moment - CountdownMath.day - 1) == .daysAndHours(days: 1, hours: 0))
        #expect(readout(at: moment - CountdownMath.day) == .clock("24:00:00"))
        #expect(readout(at: moment - duration(hours: 13, minutes: 42, seconds: 7.5)) == .clock("13:42:08"))
    }

    @Test func todayThenDaysSince() {
        #expect(readout(at: moment) == .today)
        #expect(readout(at: date(losAngeles, 2026, 12, 19, 23, 59, 59)) == .today)
        #expect(readout(at: date(losAngeles, 2026, 12, 20)) == .past(daysSince: 1))
        #expect(readout(at: date(losAngeles, 2026, 12, 22, 9)) == .past(daysSince: 3))
    }
}

struct RunwayTests {
    let la = calendar(losAngeles)
    /// Mon Aug 3 to Fri Dec 18: 137 days.
    let start = date(losAngeles, 2026, 8, 3)
    let moment = date(losAngeles, 2026, 12, 18, 18, 40)

    func runway(at now: Date, start: Date? = nil) -> CountdownMath.Runway {
        CountdownMath.runway(start: start ?? self.start, moment: moment, now: now, calendar: la)
    }

    @Test func aTickPerDayBeforeTheDay() {
        // Tue Sep 29 is day 57.
        let runway = runway(at: date(losAngeles, 2026, 9, 29, 8, 41))
        #expect(runway.scale == .days)
        #expect(runway.days == 137)
        #expect(runway.ticks.count == 136)
        #expect(runway.now == 57.5 / 137)
        #expect(runway.ticks.filter(\.isElapsed).count == 57)
        #expect(runway.ticks.first?.position == 0.5 / 137)
        #expect(runway.ticks.last?.position == 136.5 / 137)
    }

    @Test func weekendsAheadAreMarked() {
        let runway = runway(at: date(losAngeles, 2026, 9, 29, 8, 41))
        // Day 5 is Sat Aug 8, day 6 Sun Aug 9, day 7 Mon Aug 10.
        let marked = runway.ticks.filter(\.isMarked).map { Int(($0.position * 137).rounded(.down)) }
        #expect(marked.prefix(3) == [5, 6, 12])
        // 19 whole weeks from Monday to Sunday, then Monday to Thursday.
        #expect(marked.count == 19 * 2)
    }

    @Test func labelsAreTheStartAndEachFirstOfAMonth() {
        let runway = runway(at: date(losAngeles, 2026, 9, 29, 8, 41))
        let days = runway.labels.map { la.component(.day, from: $0.date) }
        let months = runway.labels.map { la.component(.month, from: $0.date) }
        #expect(months == [8, 9, 10, 11, 12])
        #expect(days == [3, 1, 1, 1, 1])
        #expect(runway.labels[1].position == 29.5 / 137)
    }

    @Test func beforeTheStartNothingHasElapsed() {
        let runway = runway(at: date(losAngeles, 2026, 8, 1))
        #expect(runway.now == nil)
        #expect(runway.ticks.count == 137)
        #expect(runway.ticks.filter(\.isElapsed).isEmpty)
    }

    @Test func onTheDayItselfEveryTickHasElapsed() {
        let runway = runway(at: moment + 60)
        #expect(runway.scale == .days)
        #expect(runway.now == nil)
        #expect(runway.ticks.count == 137)
        #expect(runway.ticks.filter(\.isElapsed).count == 137)
    }

    @Test func spansOverHalfAYearTickEachWeek() {
        // Mon Jun 1 to Dec 18: 200 days, so 29 weeks.
        let runway = runway(at: date(losAngeles, 2026, 9, 29, 8, 41), start: date(losAngeles, 2026, 6, 1))
        #expect(runway.scale == .weeks)
        #expect(runway.days == 200)
        #expect(runway.ticks.count == 28)
        // Sep 29 is day 120, in week 17.
        #expect(runway.now == 17.5 / 29)
        // Weeks holding Jul 1 (day 30), Aug 1 (61), Sep 1 (92), Nov 1 (153) and Dec 1 (183). Oct 1
        // (122) falls in now's week, which has no tick.
        let marked = runway.ticks.filter(\.isMarked).map { Int(($0.position * 29).rounded(.down)) }
        #expect(marked == [4, 8, 13, 21, 26])
    }

    @Test func theFinalDayTicksEachHour() {
        let now = moment - duration(hours: 13, minutes: 42)
        let runway = runway(at: now)
        #expect(runway.scale == .hours)
        // 7 PM on Dec 17 to 6 PM on Dec 18.
        #expect(runway.ticks.count == 24)
        #expect(runway.ticks.first?.position == duration(minutes: 20) / CountdownMath.day)
        #expect(runway.now == duration(hours: 10, minutes: 18) / CountdownMath.day)
        #expect(runway.ticks.filter(\.isMarked).count == 1)  // midnight
        let hours = runway.labels.map { la.component(.hour, from: $0.date) }
        #expect(hours == [0, 6, 12, 18])
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

    @Test func hoursChangeOnWholeHoursBeforeTheMoment() throws {
        let boundary = moment - duration(days: 6, hours: 14)
        let next = try #require(nextChange(at: moment - duration(days: 6, hours: 14, minutes: 30)))
        #expect(next > boundary)
        #expect(next < boundary + 0.001)
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
            let justBefore = CountdownMath.menuBarDisplay(moment: moment, style: style, now: max(now, Date(timeIntervalSinceReferenceDate: next.timeIntervalSinceReferenceDate.nextDown)), calendar: la)
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
        #expect(units.weekdays == 5)
    }

    @Test func todayCountsAndTheDayItselfDoesnt() {
        let units = CountdownMath.otherUnits(moment: saturday, now: date(losAngeles, 2026, 12, 12, 10), calendar: la)
        #expect(units.weekends == 1)
        #expect(units.weekdays == 5)
    }

    @Test func longCountdown() {
        // Tue Sep 29 to Sat Dec 19: 81 days, 11 weeks and 4 days (Tue to Fri).
        let units = CountdownMath.otherUnits(moment: saturday, now: date(losAngeles, 2026, 9, 29, 10, 41), calendar: la)
        #expect(units.weekends == 11)
        #expect(units.weekdays == 11 * 5 + 4)
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
        sameDay.startDate = date(losAngeles, 2026, 12, 19)
        #expect(CountdownMath.validate(sameDay, now: now, calendar: la) == .startNotBeforeMoment)
        sameDay.targetDate = date(losAngeles, 2026, 12, 19, 18, 40)
        #expect(CountdownMath.validate(sameDay, now: now, calendar: la) == nil)
    }
}


struct TimeBoundaryRegressionTests {
    let la = calendar(losAngeles)
    let moment = utc("2027-03-15T07:15:00Z")

    @Test func exactHourAndWeekDoNotRoundDownEarly() {
        #expect(CountdownMath.readout(moment: moment, now: moment - CountdownMath.week, calendar: la) == .daysAndHours(days: 7, hours: 0))
        #expect(CountdownMath.menuBarDisplay(moment: moment, style: .daysAndHours, now: moment - 3600, calendar: la).text == .remaining("1h"))
        #expect(CountdownMath.menuBarDisplay(moment: moment, style: .daysAndHours, now: moment - 3599.9, calendar: la).text == .remaining("<1h"))
        #expect(CountdownMath.exactRemainingText(3600) == "01h 00m 00s")
    }

    @Test func finalFractionalSecondDoesNotShowZero() {
        #expect(CountdownMath.readout(moment: moment, now: moment - 0.001, calendar: la) == .clock("00:00:01"))
        #expect(CountdownMath.nextSecondChange(moment: moment, now: moment - 0.001) == moment)
        #expect(CountdownMath.readout(moment: moment, now: moment, calendar: la) == .today)
        #expect(CountdownMath.nextSecondChange(moment: moment, now: moment) == nil)
        #expect(CountdownMath.exactRemainingText(-1) == "00h 00m 00s")
    }

    @Test func exactly24HoursIsNotAZeroClock() {
        #expect(CountdownMath.readout(moment: moment, now: moment - 86400, calendar: la) == .clock("24:00:00"))
        #expect(CountdownMath.menuBarDisplay(moment: moment, style: .adaptive, now: moment - 86400, calendar: la).text == .remaining("24:00:00"))
        #expect(CountdownMath.menuBarDisplay(moment: moment, style: .alwaysSeconds, now: moment - 86400, calendar: la).text == .remaining("1d 00:00:00"))
    }

    @Test func springForwardCanReachTheDayAfterTomorrowInUnder24Hours() {
        let now = date(losAngeles, 2027, 3, 13, 23, 45)
        #expect(moment.timeIntervalSince(now) == 23.5 * 3600)
        #expect(CountdownMath.calendarDays(from: now, to: moment, calendar: la) == 2)
        let fullDate = moment.formatted(Date.FormatStyle(calendar: la, timeZone: la.timeZone)
            .year().month(.abbreviated).day().hour().minute())
        #expect(CountdownMath.untilText(moment: moment, now: now, calendar: la) == String(localized: "Until \(fullDate)"))
    }

    @Test func weekdaysIncludeHolidaysButExcludeSaturdayAndSunday() {
        // Dec 24-27: Thu and Fri count, regardless of the public holiday on Friday Dec 25.
        let units = CountdownMath.otherUnits(moment: date(losAngeles, 2026, 12, 28),
                                             now: date(losAngeles, 2026, 12, 24, 12), calendar: la)
        #expect(units.weekdays == 2)
        #expect(units.weekends == 1)
    }

}
