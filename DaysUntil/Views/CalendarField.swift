import SwiftUI

/// A date row whose field opens our own calendar inside the group, under the field. SwiftUI's
/// graphical date picker can't disable single days or say what a choice means, and this one does
/// both.
///
/// Keyboard: while the calendar is open, the arrow keys move by day and week, Page Up and Page Down
/// by month, T jumps to today, Return picks and Esc closes. The field still takes typing: any date
/// the system can read, like "Dec 20" or "12/20/2026", picked with Return.
struct CalendarField<Focus: Hashable>: View {
    let title: LocalizedStringKey
    /// The start of the chosen day on the Mac's clock.
    @Binding var date: Date
    @Binding var isOpen: Bool
    var focus: FocusState<Focus?>.Binding
    let field: Focus
    let isEnabled: (Date) -> Bool
    /// The line under the grid, saying what the chosen day means.
    let caption: (Date) -> Text
    var error: Text?

    @State private var text = ""
    /// The first day of the month on show.
    @State private var month = Date()

    private var calendar: Calendar { .local }

    var body: some View {
        VStack(spacing: 0) {
            FormRow(title: title) {
                dateField
            }
            if let error {
                FieldError(text: error)
            }
            if isOpen {
                VStack(spacing: 6) {
                    MonthGrid(month: $month, selection: date, isEnabled: isEnabled, pick: pick)
                    caption(date)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .onKeyDown(handleKey)
            }
        }
        .onAppear {
            text = formatted(date)
            month = firstOfMonth(date)
        }
        .onChange(of: date) { date in
            text = formatted(date)
            month = firstOfMonth(date)
        }
        .onChange(of: isOpen) { isOpen in
            if isOpen {
                month = firstOfMonth(date)
            } else {
                text = formatted(date)
            }
        }
    }

    private var dateField: some View {
        HStack(spacing: 5) {
            // The hidden text sizes the field to what it holds.
            Text(text.isEmpty ? " " : text)
                .hidden()
                .overlay {
                    TextField(title, text: $text)
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .focused(focus, equals: field)
                        .onChange(of: text) { text in
                            if text != formatted(date), !isOpen {
                                isOpen = true
                            }
                        }
                }
            Button {
                if isOpen {
                    isOpen = false
                } else {
                    focus.wrappedValue = field
                    isOpen = true
                }
            } label: {
                Image(systemName: isOpen ? "chevron.up" : "calendar")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .accessibilityLabel(isOpen ? Text("Close Calendar") : Text("Show Calendar"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 8)
        .frame(height: 24)
        .fieldBackground(isActive: isOpen, isInvalid: error != nil)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard focus.wrappedValue == field else { return false }
        // Once something's typed, the arrows and T edit the text instead.
        let untouched = text == formatted(date)
        switch event.key {
        case .left where untouched: move(.day, by: -1)
        case .right where untouched: move(.day, by: 1)
        case .up: move(.day, by: -7)
        case .down: move(.day, by: 7)
        case .pageUp: move(.month, by: -1)
        case .pageDown: move(.month, by: 1)
        case .returnKey:
            if !untouched {
                guard let typed = parse(text), isEnabled(typed) else {
                    NSSound.beep()
                    return true
                }
                date = typed
            }
            isOpen = false
        case .escape:
            isOpen = false
        default:
            guard untouched, event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                  event.charactersIgnoringModifiers?.lowercased() == "t"
            else { return false }
            // Today can't always be picked, e.g. for a countdown without a time, but its month still shows.
            let today = calendar.startOfDay(for: Date())
            if isEnabled(today) {
                date = today
            }
            month = firstOfMonth(today)
        }
        return true
    }

    private func move(_ unit: Calendar.Component, by amount: Int) {
        guard let moved = calendar.date(byAdding: unit, value: amount, to: date).map(calendar.startOfDay), isEnabled(moved) else {
            NSSound.beep()
            return
        }
        date = moved
    }

    private func pick(_ day: Date) {
        guard isEnabled(day) else {
            NSSound.beep()
            return
        }
        date = day
        isOpen = false
    }

    /// Reads a typed date, e.g. "Dec 20", "12/20/2026" or "next Friday".
    private func parse(_ text: String) -> Date? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let match = detector?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        return match?.date.map(calendar.startOfDay)
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day().year())
    }

    private func firstOfMonth(_ date: Date) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? date
    }
}

/// Six weeks, always, so paging months never moves the rows below. Days that can't be picked are
/// disabled, today's number takes the accent colour, and the chosen day is a filled accent circle.
private struct MonthGrid: View {
    @Binding var month: Date
    let selection: Date
    let isEnabled: (Date) -> Bool
    let pick: (Date) -> Void

    private var calendar: Calendar { .local }

    var body: some View {
        let days = gridDays
        VStack(spacing: 0) {
            HStack {
                Text(month.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.wide).year()))
                    .font(.headline)
                Spacer()
                pageButton("chevron.left", label: "Previous Month", by: -1)
                pageButton("chevron.right", label: "Next Month", by: 1)
            }
            .padding(.bottom, 8)

            HStack(spacing: 0) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.micro)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 4)
            .accessibilityHidden(true)

            ForEach(0..<6, id: \.self) { week in
                HStack(spacing: 0) {
                    ForEach(days[week * 7..<week * 7 + 7], id: \.self) { day in
                        DayCell(
                            day: day,
                            isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                            isSelected: calendar.isDate(day, inSameDayAs: selection),
                            isToday: calendar.isDateInToday(day),
                            isEnabled: isEnabled(day),
                            pick: pick
                        )
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    /// 42 days, starting on the locale's first weekday on or before the 1st.
    private var gridDays: [Date] {
        let leading = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let first = calendar.date(byAdding: .day, value: -leading, to: month) ?? month
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: first).map(calendar.startOfDay) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    private func pageButton(_ systemImage: String, label: LocalizedStringKey, by amount: Int) -> some View {
        Button {
            month = calendar.date(byAdding: .month, value: amount, to: month) ?? month
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Color.well, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(Text(label))
    }
}

private struct DayCell: View {
    let day: Date
    let isInMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let isEnabled: Bool
    let pick: (Date) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            pick(day)
        } label: {
            Text(day.formatted(.dateTime.day()))
                .font(isToday ? .body.weight(.semibold) : .body)
                .monospacedDigit()
                .foregroundStyle(foreground)
                .frame(width: 28, height: 28)
                .background(background, in: Circle())
                .frame(height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(day.formatted(date: .complete, time: .omitted)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        if isSelected { return .white }
        if !isEnabled || !isInMonth { return Color(nsColor: .tertiaryLabelColor) }
        if isToday { return .accentColor }
        // Weekends are secondary, like the taller weekend ticks on the runway.
        let weekday = Calendar.local.component(.weekday, from: day)
        return weekday == 1 || weekday == 7 ? Color(nsColor: .secondaryLabelColor) : .primary
    }

    private var background: Color {
        if isSelected { return .accentColor }
        return isHovered && isEnabled ? .well : .clear
    }
}
