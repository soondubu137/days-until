import Foundation

/// A civil date and any uncommitted text. Save reads the text too, so clicking Save cannot use
/// a stale date. Invalid text remains visible until corrected or explicitly cancelled.
nonisolated struct DateEntry: Equatable {
    private(set) var selected: CalendarDay
    var text: String?

    init(_ day: CalendarDay) { selected = day }

    var day: CalendarDay? {
        if let text { return Self.parse(text) }
        return selected
    }
    var isValid: Bool { day != nil }
    var displayText: String { text ?? Self.format(selected) }

    mutating func select(_ day: CalendarDay) {
        selected = day
        text = nil
    }

    @discardableResult mutating func commit() -> Bool {
        guard let day else { return false }
        select(day)
        return true
    }

    mutating func cancelTyping() { text = nil }

    static func format(_ day: CalendarDay, locale: Locale = .current) -> String {
        CountdownMath.startOfDay(day, in: .gmt).formatted(displayStyle.locale(locale))
    }

    private static var displayStyle: Date.FormatStyle {
        Date.FormatStyle(calendar: .editor, timeZone: .gmt).weekday(.abbreviated).month(.abbreviated).day().year()
    }

    /// Complete, unambiguous ISO dates, or a complete date in the user's locale. Never accept a
    /// substring (e.g. a valid date followed by garbage) or normalize an impossible date.
    static func parse(_ input: String, locale: Locale = .current) -> CalendarDay? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.range(of: #"^[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}$"#, options: .regularExpression) != nil {
            let values = text.split(separator: "-").compactMap { Int($0) }
            guard values.count == 3 else { return nil }
            let day = CalendarDay(year: values[0], month: values[1], day: values[2])
            return CountdownMath.validStartOfDay(day, in: .gmt) == nil ? nil : day
        }
        // A complete round trip rejects trailing text, a mismatched weekday, normalized dates and
        // implicit/missing year components. ISO above remains available in every locale.
        let normalized = { (s: String) in s.lowercased().filter { !$0.isWhitespace && !$0.isPunctuation } }
        // The field's own text first, so a date edited in place reads back in every locale.
        let display = displayStyle.locale(locale)
        if let date = try? Date(text, strategy: display), normalized(date.formatted(display)) == normalized(text) {
            return CountdownMath.calendarDay(of: date, in: .gmt)
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = .editor
        formatter.timeZone = .gmt
        formatter.isLenient = false
        let formats = ["yMd", "yMMMd", "yMMMMd", "yMMMMEEEEd"].compactMap {
            DateFormatter.dateFormat(fromTemplate: $0, options: 0, locale: locale)
        }
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: text), normalized(formatter.string(from: date)) == normalized(text) {
                return CountdownMath.calendarDay(of: date, in: .gmt)
            }
        }
        return nil
    }
}

extension Calendar {
    /// Picker values are civil components carried in UTC, never actual event instants. This
    /// calendar has no DST gaps and keeps Gregorian storage independent of the system calendar.
    nonisolated static var editor: Calendar {
        var calendar = CountdownMath.gregorian(in: .gmt)
        calendar.locale = .current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }
}
