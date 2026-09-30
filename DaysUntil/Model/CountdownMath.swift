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
            let clock = "\(pad(seconds / 3_600 % 24)):\(pad(seconds / 60 % 60)):\(pad(seconds % 60))"
            return MenuBarDisplay(
                text: .remaining(days > 0 ? "\(days)d \(clock)" : clock),
                nextChange: moment - TimeInterval(seconds)
            )
        }
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
