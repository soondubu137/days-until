import Foundation

/// Wall-clock components in one explicit input zone. The place is display-only. The form uses
/// neutral UTC picker values; actual instants are resolved strictly only at this boundary.
struct Draft {
    var name = ""
    var icon = CountdownIcon.default
    var dateInput: DateEntry
    var hasTime = false
    var time = TimeOfDay(hour: 9, minute: 0)
    var hasPlace = false
    var place: Place?
    var startInput: DateEntry
    var openAtLogin = true
    private(set) var timeZone: TimeZone
    /// The selected absolute occurrence disambiguates fall-back times without assuming a 1h jump.
    var occurrence: Date?
    private var original: Countdown?
    private var originalDay: CalendarDay?
    private var originalTime: TimeOfDay?
    private var originalStartDay: CalendarDay?

    init(now: Date = Date(), timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        let calendar = CountdownMath.gregorian(in: timeZone)
        let today = CountdownMath.calendarDay(of: now, in: timeZone)
        let nextMonth = calendar.date(byAdding: .month, value: 1, to: now) ?? now
        dateInput = DateEntry(CountdownMath.calendarDay(of: nextMonth, in: timeZone))
        startInput = DateEntry(today)
    }

    init(editing countdown: Countdown, timeZone: TimeZone = .current) {
        self.timeZone = timeZone
        name = countdown.name
        icon = countdown.icon
        let day = CountdownMath.calendarDay(of: countdown.targetDate, in: timeZone)
        let clock = CountdownMath.timeOfDay(of: countdown.targetDate, in: timeZone)
        let from = CountdownMath.calendarDay(of: countdown.startDate, in: timeZone)
        dateInput = DateEntry(day)
        time = clock
        hasTime = countdown.showsTime
        hasPlace = countdown.place != nil
        place = countdown.place
        startInput = DateEntry(from)
        occurrence = countdown.targetDate
        original = countdown
        originalDay = day
        originalTime = clock
        originalStartDay = from
    }

    init(after countdown: Countdown, now: Date = Date(), timeZone: TimeZone = .current) {
        self.init(now: now, timeZone: timeZone)
        name = countdown.name
        icon = countdown.icon
        hasPlace = countdown.place != nil
        place = countdown.place
    }

    var candidates: [Date] {
        guard let day = dateInput.day else { return [] }
        return CountdownMath.possibleMoments(on: day, at: time, in: timeZone)
    }

    var targetDate: Date? {
        guard let day = dateInput.day else { return nil }
        // Preserve even a date-only target that is no longer midnight after travelling, and any
        // seconds or repeated-time occurrence, when only the name/icon/place was edited.
        if let original, day == originalDay, hasTime == original.showsTime,
           !hasTime || (time == originalTime && occurrence == original.targetDate) { return original.targetDate }
        return moment(on: day)
    }

    func moment(on day: CalendarDay) -> Date? {
        guard hasTime else { return CountdownMath.validStartOfDay(day, in: timeZone) }
        let matches = CountdownMath.possibleMoments(on: day, at: time, in: timeZone)
        if matches.count == 1 { return matches[0] }
        return occurrence.flatMap { matches.contains($0) ? $0 : nil }
    }

    var startDate: Date? {
        guard let day = startInput.day else { return nil }
        if let original, day == originalStartDay { return original.startDate }
        return CountdownMath.validStartOfDay(day, in: timeZone)
    }

    var countdown: Countdown? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let targetDate, let startDate,
              !hasPlace || place?.timeZone != nil else { return nil }
        var displayPlace = hasPlace ? place : nil
        if let place = displayPlace, place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            displayPlace?.name = PlaceSearch.city(of: place.timeZoneID)
        }
        return Countdown(name: name, icon: icon, targetDate: targetDate, showsTime: hasTime,
                         place: displayPlace, startDate: startDate)
    }

    /// Save checks the actual click time, independently of the UI's refresh interval.
    func validatedCountdown(now: Date) -> Countdown? {
        guard let countdown, CountdownMath.validate(countdown, now: now,
              calendar: CountdownMath.gregorian(in: timeZone)) == nil else { return nil }
        return countdown
    }

    /// On a system zone change, valid work is converted, preserving both instants. Invalid typed
    /// input is kept in its explicitly labelled input zone so it is never silently reinterpreted.
    mutating func changeTimeZone(to zone: TimeZone) {
        guard zone != timeZone, let targetDate, let startDate else { return }
        let snapshot = Countdown(name: name, icon: icon, targetDate: targetDate, showsTime: hasTime,
                                 place: place, startDate: startDate)
        let enabledPlace = hasPlace
        let login = openAtLogin
        self = Draft(editing: snapshot, timeZone: zone)
        hasPlace = enabledPlace
        openAtLogin = login
    }
}
