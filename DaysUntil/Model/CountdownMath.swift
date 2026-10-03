import Foundation

/// Every date calculation in the app. Nothing here reads the clock or the system time zone:
/// `now` and the Mac's calendar (carrying the Mac's current time zone) always come in as inputs.
nonisolated enum CountdownMath {
    static let day: TimeInterval = 86_400
    static let week: TimeInterval = 7 * day

    // MARK: - Resolving the moment

    /// Reading or changing either display zone never changes these instants.
    static func moment(of countdown: Countdown, calendar: Calendar) -> Date { countdown.targetDate }
    static func start(of countdown: Countdown, calendar: Calendar) -> Date { countdown.startDate }

    /// Strict wall-clock resolution for user input. Zero matches means an invalid/skipped time;
    /// two matches means the user must choose which occurrence they mean.
    static func possibleMoments(on day: CalendarDay, at time: TimeOfDay, in zone: TimeZone) -> [Date] {
        guard (0..<24).contains(time.hour), (0..<60).contains(time.minute),
              let start = validStartOfDay(day, in: zone) else { return [] }
        let wallClock = date(day, at: time, in: .gmt)
        // Calendar.nextDate(.last) returns the first occurrence for Lord Howe's half-hour
        // rollback on some Foundation versions. Derive candidates from the actual zone offsets
        // instead. Every accepted candidate must round-trip to all the requested components.
        let lower = wallClock - 2 * Self.day
        let upper = wallClock + 2 * Self.day
        var offsets: Set<Int> = [zone.secondsFromGMT(for: lower), zone.secondsFromGMT(for: upper),
                                 zone.secondsFromGMT(for: start)]
        var cursor = lower
        while let transition = zone.nextDaylightSavingTimeTransition(after: cursor), transition <= upper {
            offsets.insert(zone.secondsFromGMT(for: transition - 1))
            offsets.insert(zone.secondsFromGMT(for: transition))
            cursor = transition + 1
        }
        return offsets.map { wallClock - TimeInterval($0) }.filter {
            calendarDay(of: $0, in: zone) == day && timeOfDay(of: $0, in: zone) == time
        }.sorted()
    }

    /// Reject normalized dates (Feb 30, a skipped civil day). A skipped midnight may start at 1 AM.
    static func validStartOfDay(_ day: CalendarDay, in zone: TimeZone) -> Date? {
        guard (1...9999).contains(day.year), (1...12).contains(day.month), (1...31).contains(day.day) else { return nil }
        let start = startOfDay(day, in: zone)
        return calendarDay(of: start, in: zone) == day ? start : nil
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
        // Compare the local dates, not their first instants: where daylight saving skips midnight,
        // the day starts at 1 AM, less than a whole day before the next one starts.
        let startDay = startOfDay(calendarDay(of: start, in: calendar.timeZone), in: .gmt)
        let endDay = startOfDay(calendarDay(of: end, in: calendar.timeZone), in: .gmt)
        return gregorian(in: .gmt).dateComponents([.day], from: startDay, to: endDay).day ?? 0
    }

    /// The days the count shows: the nights left, but before the day itself never fewer than the
    /// whole days of real time left. Seven days of real time can span six nights when the clocks
    /// go back, and the count would then rise as it reaches the final week's days and hours.
    static func daysLeft(from now: Date, to moment: Date, calendar: Calendar) -> Int {
        let nights = calendarDays(from: now, to: moment, calendar: calendar)
        return nights == 0 ? 0 : max(nights, remainingSeconds(moment.timeIntervalSince(now)) / 86_400)
    }

    /// When `daysLeft` next drops: at a local midnight, or as a whole day of real time runs out.
    static func nextDaysLeftChange(from now: Date, to moment: Date, calendar: Calendar) -> Date {
        let days = daysLeft(from: now, to: moment, calendar: calendar)
        var next = now
        repeat {
            let wholeDays = remainingSeconds(moment.timeIntervalSince(next)) / 86_400
            next = min(endOfDay(containing: next, calendar: calendar), moment - TimeInterval(wholeDays * 86_400 - 1))
        } while next < moment && daysLeft(from: next, to: moment, calendar: calendar) == days
        return next
    }

    static func endOfDay(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .day, for: date)?.end ?? calendar.startOfDay(for: date) + day
    }

    /// Seconds round up: the clock reaches zero at the target, never before it.
    static func remainingSeconds(_ remaining: TimeInterval) -> Int {
        Int(max(remaining, 0).rounded(.up))
    }

    /// The whole hours in `remainingSeconds`, so the hours always agree with the seconds clock and
    /// the ticking line. An exact 7 days is 7 days, not 6 days 23 hours.
    static func wholeHours(_ remaining: TimeInterval) -> Int {
        remainingSeconds(remaining) / 3_600
    }

    static func nextSecondChange(moment: Date, now: Date) -> Date? {
        let seconds = remainingSeconds(moment.timeIntervalSince(now))
        return seconds > 0 ? moment - TimeInterval(seconds - 1) : nil
    }

    /// Whole hours drop with the second that leaves less than `hours` whole hours.
    private static func nextHourChange(moment: Date, hours: Int) -> Date {
        moment - TimeInterval(hours * 3_600 - 1)
    }

    /// Real elapsed time left, as the popover's ticking line: `80d 07h 58m 13s`, or `07h 58m 13s` on the last day.
    static func exactRemainingText(_ remaining: TimeInterval) -> String {
        let seconds = remainingSeconds(remaining)
        let days = seconds / 86_400
        let time = String(
            localized: "\(pad(seconds / 3_600 % 24))h \(pad(seconds / 60 % 60))m \(pad(seconds % 60))s",
            comment: "Hours, minutes and seconds, each two digits, as short as possible."
        )
        return days > 0 ? String(localized: "\(days)d \(time)", comment: "Days left, as short as possible, then the rest.") : time
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
            let days = daysLeft(from: now, to: moment, calendar: calendar)
            if days == 0 {
                // Days only, on the day itself: "Today" until the day ends.
                return MenuBarDisplay(text: .today, nextChange: endOfMomentDay)
            }
            var next = nextDaysLeftChange(from: now, to: moment, calendar: calendar)
            if style == .adaptive {
                next = min(next, moment - week)
            }
            let text = String(localized: "\(days)d", comment: "A number of days, as short as possible.")
            return MenuBarDisplay(text: .remaining(text), nextChange: next)

        case .adaptive where remaining > day, .daysAndHours:
            let hours = wholeHours(remaining)
            let text =
                if hours >= 24 { String(localized: "\(hours / 24)d \(hours % 24)h", comment: "Days and hours, as short as possible.") }
                else if hours > 0 { String(localized: "\(hours)h", comment: "A number of hours, as short as possible.") }
                else { String(localized: "<1h", comment: "Less than an hour left, as short as possible.") }
            var next = hours > 0 ? nextHourChange(moment: moment, hours: hours) : moment
            if style == .adaptive { next = min(next, moment - day) }
            return MenuBarDisplay(text: .remaining(text), nextChange: next)

        case .adaptive, .alwaysSeconds, .iconOnly:
            let seconds = remainingSeconds(remaining)
            let days = seconds / 86_400
            let clock = clockText(seconds, wrapsDays: style != .adaptive)
            return MenuBarDisplay(
                text: .remaining(style == .alwaysSeconds && days > 0
                    ? String(localized: "\(days)d \(clock)", comment: "Days left, as short as possible, then the rest.")
                    : clock),
                nextChange: nextSecondChange(moment: moment, now: now)
            )
        }
    }

    /// The part of `seconds` under a day as a clock: `13:42:07`.
    static func clockText(_ seconds: Int, wrapsDays: Bool = true) -> String {
        let hours = wrapsDays ? seconds / 3_600 % 24 : seconds / 3_600
        return "\(pad(hours)):\(pad(seconds / 60 % 60)):\(pad(seconds % 60))"
    }

    // MARK: - Popover readout

    /// The popover's big readout. It climbs the same ladder as the adaptive menu bar text.
    nonisolated enum Readout: Equatable, Sendable {
        /// More than a week out: days left, as `daysLeft` counts them.
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
            return .days(daysLeft(from: now, to: moment, calendar: calendar))
        }
        if remaining > day {
            let hours = wholeHours(remaining)
            return .daysAndHours(days: hours / 24, hours: hours % 24)
        }
        return .clock(clockText(remainingSeconds(remaining), wrapsDays: false))
    }

    /// Less than 24 elapsed hours can cross two midnights during spring-forward. Only call the
    /// next calendar day "tomorrow"; otherwise give the actual local date.
    static func untilText(moment: Date, now: Date, calendar: Calendar) -> String {
        let time = moment.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).hour().minute())
        switch calendarDays(from: now, to: moment, calendar: calendar) {
        case 0: return String(localized: "Until \(time) today")
        case 1: return String(localized: "Until \(time) tomorrow")
        default:
            let date = moment.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                .year().month(.abbreviated).day().hour().minute())
            return String(localized: "Until \(date)")
        }
    }

    /// The line under Today: "Reached at 9:40 AM · 6:40 PM in Tokyo". It's the day itself, so the
    /// date goes without saying, except for a date-only countdown still at midnight, which shows
    /// its day. The place's time takes its weekday only when the moment fell on another day there.
    static func reachedText(moment: Date, showsTime: Bool, place: Place?, calendar: Calendar) -> String {
        let local = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
        let reached =
            if showsTime || calendar.startOfDay(for: moment) != moment {
                String(localized: "Reached at \(moment.formatted(local.hour().minute()))")
            } else {
                String(localized: "Reached \(moment.formatted(local.weekday(.abbreviated).month(.abbreviated).day()))")
            }
        guard let place, let zone = place.timeZone else { return reached }
        let there = Date.FormatStyle(calendar: gregorian(in: zone), timeZone: zone).hour().minute()
        let sameDay = calendarDay(of: moment, in: zone) == calendarDay(of: moment, in: calendar.timeZone)
        let time = moment.formatted(sameDay ? there : there.weekday(.abbreviated))
        return String(
            localized: "\(reached) · \(time) in \(place.name)",
            comment: "When the countdown was reached, then the time then at the second time zone's place, e.g. Tokyo."
        )
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
            /// A weekend day, a week holding the first of a month, or a day's first instant. Taller while ahead.
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
        // On a 25-hour day, the moment's own day can begin with more than 24 hours left. Now then
        // waits at the destination, past every day before it.
        let nowPosition = (0..<slots).contains(today) ? position(today) : today == slots && remaining > 0 ? 1 : nil
        return Runway(
            scale: weekly ? .weeks : .days,
            ticks: ticks,
            now: nowPosition,
            labels: labels.map { Runway.Label(position: position(slot($0.index)), date: $0.date) },
            days: days
        )
    }

    /// The final 24 hours, with a tick on each clock hour and each civil day's first instant.
    private static func hourRunway(moment: Date, now: Date, calendar: Calendar, days: Int) -> Runway {
        let start = moment - day
        let wholeHour = DateComponents(minute: 0, second: 0)
        var dates: Set<Date> = []
        var hour = calendar.nextDate(after: start, matching: wholeHour, matchingPolicy: .nextTime)
        while let date = hour, date < moment {
            dates.insert(date)
            hour = calendar.nextDate(after: date, matching: wholeHour, matchingPolicy: .nextTime)
        }
        // A day can begin at 01:00, or even 00:15. Include its real boundary independently of
        // the hourly ticks; a repeated midnight still marks the start of the day only once.
        var boundary = endOfDay(containing: start, calendar: calendar)
        while boundary < moment {
            dates.insert(boundary)
            let next = endOfDay(containing: boundary, calendar: calendar)
            guard next > boundary else { break }
            boundary = next
        }
        var ticks: [Runway.Tick] = []
        var labels: [Runway.Label] = []
        var labelledClocks: Set<Int> = []
        for date in dates.sorted() {
            let position = date.timeIntervalSince(start) / day
            let hourOfDay = calendar.component(.hour, from: date)
            let isDayStart = date == calendar.startOfDay(for: date)
            ticks.append(Runway.Tick(position: position, isElapsed: date <= now, isMarked: isDayStart))
            // A clock reading repeated as the clocks go back is labelled once, where it first occurs.
            let clock = hourOfDay * 60 + calendar.component(.minute, from: date)
            if isDayStart || hourOfDay % 6 == 0, labelledClocks.insert(clock).inserted {
                labels.append(Runway.Label(position: position, date: date))
            }
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
        var weekdays: Int
    }

    /// Weekends and weekdays count the days from today up to, not including, the moment's day:
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
            weekdays: count([2, 3, 4, 5, 6])
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
        guard offset != 0 else {
            return String(localized: "same time", comment: "The second time zone's clock reads the same as the Mac's.")
        }
        let hours = abs(offset) / 3_600
        let minutes = abs(offset) / 60 % 60
        let amount =
            if minutes == 0 { String(localized: "\(hours)h", comment: "A number of hours, as short as possible.") }
            else if hours == 0 { String(localized: "\(minutes)m", comment: "A number of minutes, as short as possible.") }
            else { String(localized: "\(hours)h \(minutes)m", comment: "Hours and minutes, as short as possible.") }
        return offset > 0
            ? String(localized: "\(amount) ahead", comment: "The second time zone's clock against the Mac's.")
            : String(localized: "\(amount) behind", comment: "The second time zone's clock against the Mac's.")
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
