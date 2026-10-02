import SwiftUI

/// The countdown's form, in the popover in place of the countdown: three groups, what, when and
/// progress. Optional fields are switches that reveal their value in place, dates open our own
/// calendar, the emoji well our own emoji picker, and errors sit under the field they're about.
struct EditView: View {
    @Binding var draft: Draft
    let now: Date
    /// First launch: there's nothing to go back to, so the form offers Quit and Open at Login instead of Cancel.
    let isNew: Bool
    let onCancel: () -> Void
    let onSave: (Countdown) -> Void

    enum Field: Hashable {
        case name, emojiSearch, date, countingFrom, placeSearch, placeName
    }

    @FocusState private var focus: Field?
    /// The date field whose calendar is open, if any. Only one at a time.
    @State private var openCalendar: Field?
    @State private var isPickingEmoji = false
    @State private var lastSaveAttempt: Date?

    var body: some View {
        let moment = draft.targetDate
        let reference = lastSaveAttempt ?? now
        let momentIsFuture = moment.map { $0 > reference } ?? false
        let startIsBeforeMoment = draft.startDate.flatMap { start in moment.map { start < $0 } } ?? false
        let canSave = draft.validatedCountdown(now: reference) != nil

        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "New Countdown" : "Edit Countdown")
                .font(.headline)

            GroupedBox {
                FormRow(title: "Name") {
                    TextField("Name", text: $draft.name, prompt: Text("Going home"))
                        .textFieldStyle(.plain)
                        .labelsHidden()
                        .focused($focus, equals: .name)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .fieldBackground(radius: Radius.textField, isActive: focus == .name)
                }
                RowDivider()
                VStack(alignment: .leading, spacing: 8) {
                    Text("Icon")
                    IconPicker(icon: $draft.icon, isPickingEmoji: $isPickingEmoji)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, isPickingEmoji ? 8 : 12)
                if isPickingEmoji {
                    EmojiPicker(
                        selection: draft.icon.emoji,
                        focus: $focus,
                        searchField: .emojiSearch,
                        pick: { emoji in
                            draft.icon = .emoji(emoji)
                            isPickingEmoji = false
                        },
                        close: { isPickingEmoji = false }
                    )
                }
            }

            GroupedBox {
                CalendarField(
                    title: "Date",
                    entry: $draft.dateInput,
                    isOpen: calendarBinding(.date),
                    focus: $focus,
                    field: .date,
                    isEnabled: canPickDate,
                    caption: dateCaption,
                    error: targetError(isFuture: momentIsFuture)
                )
                RowDivider()
                FormRow(title: "Exact time") {
                    if draft.hasTime {
                        TimeField(time: $draft.time)
                    }
                    RowSwitch(title: "Exact time", isOn: $draft.hasTime)
                }
                if draft.hasTime, draft.candidates.count > 1 {
                    FormRow(title: "Occurrence") {
                        Picker("Occurrence", selection: occurrenceSelection) {
                            Text("Choose…").tag(nil as Date?)
                            ForEach(Array(draft.candidates.enumerated()), id: \.element) { index, instant in
                                Text(occurrenceLabel(instant, index: index)).tag(Optional(instant))
                            }
                        }
                        .labelsHidden()
                    }
                    Footnote("This time occurs twice when the clocks go back. Choose which one.")
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }
                RowDivider()
                FormRow(title: "Show another time zone") {
                    RowSwitch(title: "Show another time zone", isOn: $draft.hasPlace)
                }
                if draft.hasPlace {
                    RowDivider()
                    PlaceField(
                        place: $draft.place, now: now, focus: $focus, searchField: .placeSearch, nameField: .placeName
                    )
                }
            }
            Footnote("Date and time are in \(draft.timeZone.identifier.replacingOccurrences(of: "_", with: " ")). The saved moment stays fixed.")
            if !draft.hasTime, let moment,
               CountdownMath.gregorian(in: draft.timeZone).startOfDay(for: moment) != moment {
                Footnote("The saved moment is \(moment.formatted(Date.FormatStyle(timeZone: draft.timeZone).hour().minute())) in this time zone.")
            }
            if draft.hasPlace {
                if let place = draft.place, let zone = place.timeZone, let moment {
                    Footnote(placeNote(place, zone: zone, moment: moment))
                } else {
                    Footnote("Search by city or time zone. Return picks the highlighted place.")
                }
            }

            GroupedBox {
                CalendarField(
                    title: "Counting from",
                    entry: $draft.startInput,
                    isOpen: calendarBinding(.countingFrom),
                    focus: $focus,
                    field: .countingFrom,
                    isEnabled: { carrier in
                        guard let moment, let start = CountdownMath.validStartOfDay(
                            CountdownMath.calendarDay(of: carrier, in: .gmt), in: draft.timeZone
                        ) else { return false }
                        return start < moment
                    },
                    caption: { countingFromCaption($0, moment: moment) },
                    error: startIsBeforeMoment || moment == nil ? nil : Text("The start must be before the target time.")
                )
            }
            Footnote("Progress is measured from this day.")

            if isNew {
                Toggle("Open Days Until at login", isOn: $draft.openAtLogin)
                    .toggleStyle(.checkbox)
            }

            HStack {
                if isNew {
                    Button("Quit") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.borderless)
                    Spacer()
                    Button("Start Countdown") { save() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                } else {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    Button("Save") { save() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave)
                }
            }
            .controlSize(.large)
        }
        .padding(16)
        .onChange(of: now) { _ in lastSaveAttempt = nil }
        .onChange(of: focus) { focus in
            // The calendar follows its field: open while it has focus, closed once it hasn't.
            switch focus {
            case .date, .countingFrom: openCalendar = focus
            default: openCalendar = nil
            }
            // The emoji picker closes once another field takes focus. Its own cells and bar don't
            // take it, so they leave it open.
            if let focus, focus != .emojiSearch {
                isPickingEmoji = false
            }
        }
        .onChange(of: isPickingEmoji) { isPickingEmoji in
            if isPickingEmoji {
                // The search field appears in this same update, so focus it on the next.
                DispatchQueue.main.async { focus = .emojiSearch }
            }
        }
        .onChange(of: draft.hasPlace) { hasPlace in
            if hasPlace, draft.place == nil {
                // The search field appears in this same update, so focus it on the next.
                DispatchQueue.main.async { focus = .placeSearch }
            }
        }
        .onAppear {
            // Reading the emoji and checking each can be drawn takes a moment, so it's done before
            // the picker is first opened.
            DispatchQueue.global(qos: .utility).async { _ = EmojiCatalog.sections }
            if isNew {
                // The popover's window isn't key yet when the form first appears.
                DispatchQueue.main.async { focus = .name }
            }
        }
    }

    private func save() {
        // Finish any native time-field edit before reading its binding.
        guard NSApp.keyWindow?.makeFirstResponder(nil) != false else { return }
        let instant = Date()
        lastSaveAttempt = instant
        guard let countdown = draft.validatedCountdown(now: instant) else { return }
        onSave(countdown)
    }

    private func calendarBinding(_ field: Field) -> Binding<Bool> {
        Binding {
            openCalendar == field
        } set: { isOpen in
            openCalendar = isOpen ? field : nil
        }
    }

    // MARK: - What the choices mean

    /// "Friday, December 18 · 80 days from today".
    private func dateCaption(_ day: Date) -> Text {
        let today = CountdownMath.startOfDay(CountdownMath.calendarDay(of: Date(), in: draft.timeZone), in: .gmt)
        let days = CountdownMath.calendarDays(from: today, to: day, calendar: .editor)
        let long = longDay(day)
        switch days {
        case ..<0: return Text("Pick a date in the future.")
        case 0: return Text("\(long) · today")
        case 1: return Text("\(long) · tomorrow")
        default: return Text("\(long) · \(days) days from today")
        }
    }

    private func countingFromCaption(_ carrier: Date, moment: Date?) -> Text {
        guard let moment else { return Text("Choose the target date and time first.") }
        let start = CountdownMath.startOfDay(CountdownMath.calendarDay(of: carrier, in: .gmt), in: draft.timeZone)
        let days = CountdownMath.calendarDays(from: start, to: moment, calendar: CountdownMath.gregorian(in: draft.timeZone))
        if start >= moment { return Text("The start must be before the target time.") }
        if days == 0 { return Text("Counting from the start of the same day.") }
        return Text("\(longDay(carrier)) · \(days) days before the target")
    }

    private func canPickDate(_ carrier: Date) -> Bool {
        let day = CountdownMath.calendarDay(of: carrier, in: .gmt)
        guard let start = CountdownMath.validStartOfDay(day, in: draft.timeZone) else { return false }
        if draft.hasTime {
            // Let the user pick a DST transition day and then correct the time in its own field.
            return CountdownMath.endOfDay(containing: start, calendar: CountdownMath.gregorian(in: draft.timeZone)) > Date()
        }
        return start > Date()
    }

    private func targetError(isFuture: Bool) -> Text? {
        guard draft.dateInput.isValid else { return nil } // The date field explains parse failures.
        if draft.targetDate == nil {
            if draft.hasTime, draft.candidates.count > 1 { return Text("Choose the first or second occurrence of this time.") }
            return Text("This local time does not exist because the clocks change. Choose another time.")
        }
        return isFuture ? nil : Text("Pick a date and time in the future.")
    }

    private var occurrenceSelection: Binding<Date?> {
        Binding {
            draft.occurrence.flatMap { draft.candidates.contains($0) ? $0 : nil }
        } set: { draft.occurrence = $0 }
    }

    private func occurrenceLabel(_ date: Date, index: Int) -> String {
        let order = index == 0 ? String(localized: "First") : String(localized: "Second")
        return "\(order) · \(PlaceSearch.utcOffset(of: draft.timeZone, at: date))"
    }

    private func placeNote(_ place: Place, zone: TimeZone, moment: Date) -> Text {
        let name = place.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? PlaceSearch.city(of: place.timeZoneID) : place.name
        let there = moment.formatted(Date.FormatStyle(calendar: CountdownMath.gregorian(in: zone), timeZone: zone)
            .year().month(.abbreviated).day().hour().minute())
        return Text("The same moment is \(there) in \(name).")
    }

    private func longDay(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(calendar: .editor, timeZone: .gmt).weekday(.wide).month(.wide).day())
    }

}

/// The preset symbols in a row of wells, and a last well that opens the emoji picker under them.
private struct IconPicker: View {
    @Binding var icon: CountdownIcon
    @Binding var isPickingEmoji: Bool

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CountdownIcon.presetSymbols, id: \.self) { name in
                Button {
                    icon = .symbol(name)
                    isPickingEmoji = false
                } label: {
                    IconWell(isSelected: icon == .symbol(name)) {
                        Image(systemName: name)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(name))
                .accessibilityAddTraits(icon == .symbol(name) ? .isSelected : [])
                Spacer(minLength: 0)
            }
            Button {
                isPickingEmoji.toggle()
            } label: {
                IconWell(isSelected: icon.emoji != nil, isOpen: isPickingEmoji) {
                    if let emoji = icon.emoji {
                        Text(emoji).font(.system(size: 14))
                    } else {
                        Image(systemName: "face.smiling")
                    }
                }
            }
            .buttonStyle(.plain)
            .help(isPickingEmoji ? "Close the emoji picker" : "Choose an emoji")
            .accessibilityLabel(Text("Emoji"))
            .accessibilityAddTraits(icon.emoji != nil ? .isSelected : [])
        }
    }
}

/// An icon choice. The chosen one is accent-tinted with a ring; the emoji well is tinted while its
/// picker is open.
private struct IconWell<Content: View>: View {
    let isSelected: Bool
    var isOpen = false
    @ViewBuilder let content: Content

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.well, style: .continuous)
        content
            .font(.system(size: 12))
            .foregroundStyle(isSelected || isOpen ? Color.accentColor : .secondary)
            .frame(width: 26, height: 26)
            .background(isSelected || isOpen ? Color.accentSoft : Color.well, in: shape)
            .overlay {
                if isSelected {
                    shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
                }
            }
            .contentShape(shape)
    }
}

extension MenuBarStyle {
    var title: String {
        switch self {
        case .adaptive: String(localized: "Adaptive")
        case .daysOnly: String(localized: "Days only")
        case .daysAndHours: String(localized: "Days and hours")
        case .alwaysSeconds: String(localized: "Always show seconds")
        case .iconOnly: String(localized: "Icon only")
        }
    }
}
