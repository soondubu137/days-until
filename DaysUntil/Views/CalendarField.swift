import SwiftUI

/// A date row whose field opens our own calendar inside the group, under the field. SwiftUI's
/// graphical date picker can't disable single days or say what a choice means, and this one does
/// both.
///
/// Keyboard: while the calendar is open, the arrow keys move by day and week, Page Up and Page Down
/// by month, T jumps to today, Return picks and Esc closes. The field accepts
/// a complete local date or ISO date, like "2027-12-20". Save also reads pending text.
struct CalendarField<Focus: Hashable>: View {
    let title: LocalizedStringKey
    @Binding var entry: DateEntry
    @Binding var isOpen: Bool
    var focus: FocusState<Focus?>.Binding
    let field: Focus
    /// The zone the days are entered in, which decides which day is today.
    let timeZone: TimeZone
    let isEnabled: (Date) -> Bool
    /// The line under the grid, saying what the chosen day means.
    let caption: (Date) -> Text
    var error: Text?

    /// The first day of the month on show.
    @State private var month = Date()

    private var calendar: Calendar { .editor }

    private var date: Date {
        CountdownMath.startOfDay(entry.day ?? entry.selected, in: .gmt)
    }
    private var text: String { entry.displayText }
    /// The field writes its text back as it takes focus. Only a change counts as typing, so the
    /// arrows and T still move the day until something is typed.
    private var textBinding: Binding<String> {
        Binding { entry.displayText } set: { if $0 != entry.displayText { entry.text = $0 } }
    }
    private var fieldError: Text? {
        entry.isValid ? error : Text("Enter a date like 2027-12-19.")
    }

    var body: some View {
        VStack(spacing: 0) {
            FormRow(title: title) {
                dateField
            }
            if let fieldError {
                FieldError(text: fieldError)
            }
            if isOpen {
                VStack(spacing: 6) {
                    MonthGrid(month: $month, selection: date, timeZone: timeZone, isEnabled: isEnabled, pick: pick)
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
            month = firstOfMonth(date)
        }
        .onChange(of: date) { date in
            month = firstOfMonth(date)
        }
        .onChange(of: isOpen) { isOpen in
            if isOpen {
                month = firstOfMonth(date)
            } else {
                entry.commit()
            }
        }
    }

    private var dateField: some View {
        HStack(spacing: 5) {
            // The hidden text sizes the field to what it holds.
            Text(text.isEmpty ? " " : text)
                .hidden()
                .overlay {
                    TextField(title, text: textBinding)
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .focused(focus, equals: field)
                        .onChange(of: text) { text in
                            if entry.text != nil, !isOpen {
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
        .fieldBackground(isActive: isOpen, isInvalid: fieldError != nil)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard focus.wrappedValue == field else { return false }
        // Once something's typed, the arrows and T edit the text instead.
        let untouched = entry.text == nil
        switch event.key {
        case .left where untouched: move(.day, by: -1)
        case .right where untouched: move(.day, by: 1)
        case .up: move(.day, by: -7)
        case .down: move(.day, by: 7)
        case .pageUp: move(.month, by: -1)
        case .pageDown: move(.month, by: 1)
        case .returnKey:
            guard entry.commit(), isEnabled(date) else {
                NSSound.beep()
                return true
            }
            isOpen = false
        case .escape:
            entry.cancelTyping()
            isOpen = false
        default:
            guard untouched, event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
                  event.charactersIgnoringModifiers?.lowercased() == "t"
            else { return false }
            // Today can't always be picked, e.g. for a countdown without a time, but its month still shows.
            let today = CountdownMath.startOfDay(CountdownMath.calendarDay(of: Date(), in: timeZone), in: .gmt)
            if isEnabled(today) {
                entry.select(CountdownMath.calendarDay(of: today, in: .gmt))
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
        entry.select(CountdownMath.calendarDay(of: moved, in: .gmt))
    }

    private func pick(_ day: Date) {
        guard isEnabled(day) else {
            NSSound.beep()
            return
        }
        entry.select(CountdownMath.calendarDay(of: day, in: .gmt))
        isOpen = false
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
    let timeZone: TimeZone
    let isEnabled: (Date) -> Bool
    let pick: (Date) -> Void

    private var calendar: Calendar { .editor }

    var body: some View {
        let days = gridDays
        VStack(spacing: 0) {
            HStack {
                Text(month.formatted(Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).month(.wide).year()))
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
                            isToday: CountdownMath.calendarDay(of: day, in: .gmt) == CountdownMath.calendarDay(of: Date(), in: timeZone),
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
            // The number alone: the date's day field reads "18日" in Japanese and Chinese.
            Text(Calendar.editor.component(.day, from: day).formatted())
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
        .accessibilityLabel(Text(day.formatted(Date.FormatStyle(date: .complete, time: .omitted, calendar: .editor, timeZone: .gmt))))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        if isSelected { return .white }
        if !isEnabled || !isInMonth { return Color(nsColor: .tertiaryLabelColor) }
        if isToday { return .accentColor }
        // Weekends are secondary, like the taller weekend ticks on the runway.
        let weekday = Calendar.editor.component(.weekday, from: day)
        return weekday == 1 || weekday == 7 ? Color(nsColor: .secondaryLabelColor) : .primary
    }

    private var background: Color {
        if isSelected { return .accentColor }
        return isHovered && isEnabled ? .well : .clear
    }
}
