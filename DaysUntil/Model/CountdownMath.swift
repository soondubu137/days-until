import Foundation

/// Every date calculation in the app. Nothing here reads the clock or the system time zone:
/// `now` and the Mac's calendar (carrying the Mac's current time zone) always come in as inputs.
nonisolated enum CountdownMath {
    static let day: TimeInterval = 86_400
    static let week: TimeInterval = 7 * day

    // MARK: - Resolving the moment

    /// The zone the countdown's date and time are read in: the place's when pinned, the Mac's when floating.
    static func timeZone(of countdown: Countdown, calendar: Calendar) -> TimeZone {
        countdown.place?.timeZone ?? calendar.timeZone
    }

    /// The absolute moment the countdown runs to.
    static func moment(of countdown: Countdown, calendar: Calendar) -> Date {
        let zone = timeZone(of: countdown, calendar: calendar)
        guard let time = countdown.time else {
            return startOfDay(countdown.date, in: zone)
        }
        let components = DateComponents(
            year: countdown.date.year, month: countdown.date.month, day: countdown.date.day,
            hour: time.hour, minute: time.minute
        )
        // A time skipped by daylight saving resolves to the same wall time after the jump.
        return gregorian(in: zone).date(from: components) ?? startOfDay(countdown.date, in: zone)
    }

    /// Where the progress bar starts: the start of "counting from" on the Mac's clock.
    static func start(of countdown: Countdown, calendar: Calendar) -> Date {
        startOfDay(countdown.countingFrom, in: calendar.timeZone)
    }

    /// The first instant of `day` in `timeZone`: midnight, or 1 AM where daylight saving skips midnight.
    static func startOfDay(_ day: CalendarDay, in timeZone: TimeZone) -> Date {
        let calendar = gregorian(in: timeZone)
        let noon = DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)
        return calendar.date(from: noon).map { calendar.startOfDay(for: $0) } ?? .distantFuture
    }

    static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    // MARK: - Converting picker dates to components

    /// The Gregorian day `date` falls on in `timeZone`.
    static func calendarDay(of date: Date, in timeZone: TimeZone) -> CalendarDay {
        let parts = gregorian(in: timeZone).dateComponents([.year, .month, .day], from: date)
        return CalendarDay(year: parts.year ?? 1, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    static func timeOfDay(of date: Date, in timeZone: TimeZone) -> TimeOfDay {
        let parts = gregorian(in: timeZone).dateComponents([.hour, .minute], from: date)
        return TimeOfDay(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }

    /// A date that reads as `day` at `time` in `timeZone`, for seeding a date picker.
    static func date(_ day: CalendarDay, at time: TimeOfDay, in timeZone: TimeZone) -> Date {
        let components = DateComponents(
            year: day.year, month: day.month, day: day.day, hour: time.hour, minute: time.minute
        )
        return gregorian(in: timeZone).date(from: components) ?? startOfDay(day, in: timeZone)
    }

    // MARK: - Counting

    nonisolated enum Phase: Equatable, Sendable {
        /// Before the moment.
        case counting
        /// The moment has passed, and it's still the local day it fell on.
        case reached
        /// After that day.
        case past
    }

    static func phase(of moment: Date, now: Date, calendar: Calendar) -> Phase {
        if now < moment { return .counting }
        return now < endOfDay(containing: moment, calendar: calendar) ? .reached : .past
    }

    /// The number of local midnights from `start` to `end`: days left when `start` is now, the
    /// days since when `end` is. It changes at midnight, and for days left it equals the nights left.
    static func calendarDays(from start: Date, to end: Date, calendar: Calendar) -> Int {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        return calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
    }

    static func endOfDay(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .day, for: date)?.end ?? calendar.startOfDay(for: date) + day
    }

    /// Whole `unit`s left. The count drops at each `moment - k × unit` instant, so a timer that fires
    /// exactly on one already sees the new value. `remaining` must be positive.
    static func wholeUnits(_ remaining: TimeInterval, of unit: TimeInterval) -> Int {
        Int((remaining / unit).rounded(.up)) - 1
    }

    /// Real elapsed time left, as the popover's ticking line: `80d 07h 58m 13s`, or `07h 58m 13s` on the last day.
    static func exactRemainingText(_ remaining: TimeInterval) -> String {
        let seconds = wholeUnits(remaining, of: 1)
        let days = seconds / 86_400
        let time = "\(pad(seconds / 3_600 % 24))h \(pad(seconds / 60 % 60))m \(pad(seconds % 60))s"
        return days > 0 ? "\(days)d \(time)" : time
    }

    // MARK: - Menu bar

    nonisolated enum MenuBarText: Equatable, Sendable {
        /// `81d`, `6d 14h`, `13:42:07`, …
        case remaining(String)
        case today
        case iconOnly
    }

    nonisolated struct MenuBarDisplay: Equatable, Sendable {
        var text: MenuBarText
        /// The instant the text next changes, or nil when it never will.
        var nextChange: Date?
    }

    /// What the menu bar item shows beside the icon, and when that next changes.
    static func menuBarDisplay(
        moment: Date, style: MenuBarStyle, now: Date, calendar: Calendar
    ) -> MenuBarDisplay {
        if style == .iconOnly {
            return MenuBarDisplay(text: .iconOnly, nextChange: nil)
        }
        let remaining = moment.timeIntervalSince(now)
        let endOfMomentDay = endOfDay(containing: moment, calendar: calendar)
        guard remaining > 0 else {
            return now < endOfMomentDay
                ? MenuBarDisplay(text: .today, nextChange: endOfMomentDay)
                : MenuBarDisplay(text: .iconOnly, nextChange: nil)
        }

        switch style {
        case .adaptive where remaining > week, .daysOnly:
            let days = calendarDays(from: now, to: moment, calendar: calendar)
            if days == 0 {
                // Days only, on the day itself: "Today" until the day ends.
                return MenuBarDisplay(text: .today, nextChange: endOfMomentDay)
            }
            var next = endOfDay(containing: now, calendar: calendar)
            if style == .adaptive {
                next = min(next, moment - week)
            }
            return MenuBarDisplay(text: .remaining("\(days)d"), nextChange: next)

        case .adaptive where remaining > day, .daysAndHours:
            let hours = wholeUnits(remaining, of: 3_600)
            let text =
                if hours >= 24 { "\(hours / 24)d \(hours % 24)h" }
                else if hours > 0 { "\(hours)h" }
                else { "<1h" }
            return MenuBarDisplay(text: .remaining(text), nextChange: moment - TimeInterval(hours * 3_600))

        case .adaptive, .alwaysSeconds, .iconOnly:
            let seconds = wholeUnits(remaining, of: 1)
            let days = seconds / 86_400
            let clock = clockText(seconds)
            return MenuBarDisplay(
                text: .remaining(days > 0 ? "\(days)d \(clock)" : clock),
                nextChange: moment - TimeInterval(seconds)
            )
        }
    }

    /// The part of `seconds` under a day as a clock: `13:42:07`.
    static func clockText(_ seconds: Int) -> String {
        "\(pad(seconds / 3_600 % 24)):\(pad(seconds / 60 % 60)):\(pad(seconds % 60))"
    }

    // MARK: - Popover readout

    /// The popover's big readout. It climbs the same ladder as the adaptive menu bar text.
    nonisolated enum Readout: Equatable, Sendable {
        /// More than a week out: days left, as `calendarDays` counts them.
        case days(Int)
        /// The final week: whole hours left, split into days and hours.
        case daysAndHours(days: Int, hours: Int)
        /// The final 24 hours: `13:42:07`.
        case clock(String)
        /// The moment has passed, and it's still the local day it fell on.
        case today
        /// After that day, with the number of local midnights since the moment.
        case past(daysSince: Int)
    }

    static func readout(moment: Date, now: Date, calendar: Calendar) -> Readout {
        let remaining = moment.timeIntervalSince(now)
        guard remaining > 0 else {
            return now < endOfDay(containing: moment, calendar: calendar)
                ? .today
                : .past(daysSince: calendarDays(from: moment, to: now, calendar: calendar))
        }
        if remaining > week {
            return .days(calendarDays(from: now, to: moment, calendar: calendar))
        }
        if remaining > day {
            let hours = wholeUnits(remaining, of: 3_600)
            return .daysAndHours(days: hours / 24, hours: hours % 24)
        }
        return .clock(clockText(wholeUnits(remaining, of: 1)))
    }

    // MARK: - Runway

    /// The popover's picture of the whole journey, from the start of Counting from to the moment.
    /// Positions run from 0 at the start of the track to 1 at its end, where the moment waits.
    nonisolated struct Runway: Equatable, Sendable {
        nonisolated enum Scale: Equatable, Sendable {
            /// A tick per day.
            case days
            /// A tick per week, for spans longer than `longestDaySpan`.
            case weeks
            /// A tick per clock hour, in the final 24 hours.
            case hours
        }

        nonisolated struct Tick: Equatable, Sendable {
            var position: Double
            /// Behind now. Drawn short and faint.
            var isElapsed: Bool
            /// A weekend day, a week holding the first of a month, or midnight. Drawn taller while ahead.
            var isMarked: Bool
        }

        nonisolated struct Label: Equatable, Sendable {
            var position: Double
            /// A day for a month's name, or an hour.
            var date: Date
        }

        var scale: Scale
        /// Every tick except the one for now, which the today mark replaces.
        var ticks: [Tick]
        /// Where now falls, or nil before the first tick and after the last.
        var now: Double?
        /// Days and weeks: the start, then each first of a month. Hours: every sixth clock hour.
        var labels: [Label]
        /// Local midnights from the start to the moment, e.g. "137 days from Mon, Aug 3".
        var days: Int
    }

    static let longestDaySpan = 26 * 7

    static func runway(start: Date, moment: Date, now: Date, calendar: Calendar) -> Runway {
        let days = calendarDays(from: start, to: moment, calendar: calendar)
        let remaining = moment.timeIntervalSince(now)
        if remaining > 0, remaining <= day {
            return hourRunway(moment: moment, now: now, calendar: calendar, days: days)
        }

        // Day `index` counts from the start day, so the moment's own day is `days`.
        let startDay = calendar.startOfDay(for: start)
        let length = max(days, 1)
        let weekly = length > longestDaySpan
        let slots = weekly ? (length + 6) / 7 : length
        func slot(_ index: Int) -> Int { weekly ? Int((Double(index) / 7).rounded(.down)) : index }
        func position(_ slot: Int) -> Double { (Double(slot) + 0.5) / Double(slots) }

        var monthStarts: [(index: Int, date: Date)] = []
        var month = calendar.dateInterval(of: .month, for: startDay)?.end
        while let first = month {
            let index = calendarDays(from: startDay, to: first, calendar: calendar)
            guard index < length else { break }
            monthStarts.append((index, first))
            month = calendar.date(byAdding: .month, value: 1, to: first)
        }
        let monthSlots = Set(monthStarts.map { slot($0.index) })

        let today = slot(calendarDays(from: startDay, to: now, calendar: calendar))
        // Weekday numbers: 1 is Sunday, 7 is Saturday.
        let firstWeekday = calendar.component(.weekday, from: startDay)
        let ticks = (0..<slots).filter { $0 != today }.map { slot in
            let isMarked = weekly
                ? monthSlots.contains(slot)
                : [1, 7].contains((firstWeekday - 1 + slot) % 7 + 1)
            return Runway.Tick(position: position(slot), isElapsed: slot < today, isMarked: isMarked)
        }
        let labels = [(index: 0, date: startDay)] + monthStarts
        return Runway(
            scale: weekly ? .weeks : .days,
            ticks: ticks,
            now: (0..<slots).contains(today) ? position(today) : nil,
            labels: labels.map { Runway.Label(position: position(slot($0.index)), date: $0.date) },
            days: days
        )
    }

    /// The final 24 hours, with a tick on each clock hour.
    private static func hourRunway(moment: Date, now: Date, calendar: Calendar, days: Int) -> Runway {
        let start = moment - day
        let wholeHour = DateComponents(minute: 0, second: 0)
        var ticks: [Runway.Tick] = []
        var labels: [Runway.Label] = []
        var hour = calendar.nextDate(after: start, matching: wholeHour, matchingPolicy: .nextTime)
        while let date = hour, date < moment {
            let position = date.timeIntervalSince(start) / day
            let hourOfDay = calendar.component(.hour, from: date)
            ticks.append(Runway.Tick(position: position, isElapsed: date <= now, isMarked: hourOfDay == 0))
            if hourOfDay % 6 == 0 {
                labels.append(Runway.Label(position: position, date: date))
            }
            hour = calendar.nextDate(after: date, matching: wholeHour, matchingPolicy: .nextTime)
        }
        return Runway(
            scale: .hours,
            ticks: ticks,
            now: min(max(now.timeIntervalSince(start) / day, 0), 1),
            labels: labels,
            days: days
        )
    }

    // MARK: - Popover

    nonisolated struct OtherUnits: Equatable, Sendable {
        /// Exact time left, in weeks.
        var weeks: Double
        /// Saturdays left.
        var weekends: Int
        /// Mondays to Fridays left.
        var workdays: Int
    }

    /// Weekends and workdays count the days from today up to, not including, the moment's day:
    /// the same number of days as `calendarDays`, so today counts and the day itself doesn't.
    static func otherUnits(moment: Date, now: Date, calendar: Calendar) -> OtherUnits {
        let days = max(calendarDays(from: now, to: moment, calendar: calendar), 0)
        // Weekday numbers: 1 is Sunday, 7 is Saturday.
        let firstWeekday = calendar.component(.weekday, from: now)
        func count(_ weekdays: Set<Int>) -> Int {
            let partialWeek = (0..<days % 7).filter { weekdays.contains((firstWeekday - 1 + $0) % 7 + 1) }
            return days / 7 * weekdays.count + partialWeek.count
        }
        return OtherUnits(
            weeks: max(moment.timeIntervalSince(now), 0) / week,
            weekends: count([7]),
            workdays: count([2, 3, 4, 5, 6])
        )
    }

    /// How far `now` is from `start` to `moment`, from 0 to 1. Nil when `start` isn't before `moment`.
    static func progress(start: Date, moment: Date, now: Date) -> Double? {
        let total = moment.timeIntervalSince(start)
        guard total > 0 else { return nil }
        return min(max(now.timeIntervalSince(start) / total, 0), 1)
    }

    /// The place's clock against the Mac's: "13h ahead", "5h 30m behind", "same time".
    static func offsetText(of place: TimeZone, from local: TimeZone, at date: Date) -> String {
        let offset = place.secondsFromGMT(for: date) - local.secondsFromGMT(for: date)
        guard offset != 0 else { return "same time" }
        let hours = abs(offset) / 3_600
        let minutes = abs(offset) / 60 % 60
        let amount =
            if minutes == 0 { "\(hours)h" }
            else if hours == 0 { "\(minutes)m" }
            else { "\(hours)h \(minutes)m" }
        return offset > 0 ? "\(amount) ahead" : "\(amount) behind"
    }

    /// 6 AM to 6 PM at the place. There are no coordinates to work out real sunrise and sunset.
    static func isDaytime(in timeZone: TimeZone, at date: Date) -> Bool {
        (6..<18).contains(gregorian(in: timeZone).component(.hour, from: date))
    }

    /// Whether two zones read the same at `date`, so showing the time in both adds nothing.
    static func sameOffset(_ a: TimeZone, _ b: TimeZone, at date: Date) -> Bool {
        a.secondsFromGMT(for: date) == b.secondsFromGMT(for: date)
    }

    // MARK: - Validation

    nonisolated enum ValidationError: Error, Equatable, Sendable {
        case momentNotInFuture
        case startNotBeforeMoment
    }

    static func validate(_ countdown: Countdown, now: Date, calendar: Calendar) -> ValidationError? {
        let moment = Self.moment(of: countdown, calendar: calendar)
        if moment <= now { return .momentNotInFuture }
        if start(of: countdown, calendar: calendar) >= moment { return .startNotBeforeMoment }
        return nil
    }

    private static func pad(_ number: Int) -> String {
        number < 10 ? "0\(number)" : "\(number)"
    }
}
