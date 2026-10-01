import SwiftUI

/// The edit form's working copy. The pickers edit `Date`s on the Mac's clock; only their day and
/// time components are kept, so a pinned countdown's "6:40 PM" means 6:40 PM at the place.
struct Draft {
    var name = ""
    var icon = CountdownIcon.default
    /// The start of the chosen day.
    var date: Date
    var hasTime = false
    var time: Date
    var hasPlace = false
    var place: Place?
    /// The start of the chosen day.
    var countingFrom: Date
    /// Asked only on first launch. App settings otherwise live in the ••• menu.
    var openAtLogin = true

    /// A blank countdown a month out, counting from today.
    init(now: Date = Date()) {
        let calendar = Calendar.local
        let today = calendar.startOfDay(for: now)
        date = calendar.date(byAdding: .month, value: 1, to: today) ?? today
        time = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today) ?? today
        countingFrom = today
    }

    init(editing countdown: Countdown) {
        let local = TimeZone.current
        let time = countdown.time ?? TimeOfDay(hour: 9, minute: 0)
        name = countdown.name
        icon = countdown.icon
        date = CountdownMath.startOfDay(countdown.date, in: local)
        hasTime = countdown.time != nil
        self.time = CountdownMath.date(countdown.date, at: time, in: local)
        hasPlace = countdown.place != nil
        place = countdown.place
        countingFrom = CountdownMath.startOfDay(countdown.countingFrom, in: local)
    }

    /// Starts over after a countdown is reached, keeping what's likely to repeat: name, icon and place.
    init(after countdown: Countdown) {
        self.init()
        name = countdown.name
        icon = countdown.icon
        hasPlace = countdown.place != nil
        place = countdown.place
    }

    /// The countdown the form describes. Nil while it has no name, or a place is switched on but not picked.
    var countdown: Countdown? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !hasPlace || place != nil else { return nil }
        var countdown = resolved(on: date)
        countdown.name = name
        if let place = countdown.place, place.name.trimmingCharacters(in: .whitespaces).isEmpty {
            countdown.place?.name = PlaceSearch.city(of: place.timeZoneID)
        }
        return countdown
    }

    /// The moment the countdown would run to if its date were `day`.
    func moment(on day: Date) -> Date {
        CountdownMath.moment(of: resolved(on: day), calendar: .local)
    }

    /// The form as a countdown with `day` as its date, whatever the name.
    private func resolved(on day: Date) -> Countdown {
        let local = TimeZone.current
        return Countdown(
            name: name,
            icon: icon,
            date: CountdownMath.calendarDay(of: day, in: local),
            time: hasTime ? CountdownMath.timeOfDay(of: time, in: local) : nil,
            place: hasPlace ? place : nil,
            countingFrom: CountdownMath.calendarDay(of: countingFrom, in: local)
        )
    }
}

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

    var body: some View {
        let moment = draft.moment(on: draft.date)
        let momentIsFuture = moment > now
        let startIsBeforeMoment = draft.countingFrom < moment
        let canSave = draft.countdown != nil && momentIsFuture && startIsBeforeMoment

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
                    date: $draft.date,
                    isOpen: calendarBinding(.date),
                    focus: $focus,
                    field: .date,
                    isEnabled: { draft.moment(on: $0) > Date() },
                    caption: dateCaption,
                    error: momentIsFuture ? nil : Text("Pick a date in the future.")
                )
                RowDivider()
                FormRow(title: "Exact time") {
                    if draft.hasTime {
                        TimeField(time: $draft.time)
                    }
                    RowSwitch(title: "Exact time", isOn: $draft.hasTime)
                }
                RowDivider()
                FormRow(title: "In another time zone") {
                    RowSwitch(title: "In another time zone", isOn: $draft.hasPlace)
                }
                if draft.hasPlace {
                    RowDivider()
                    PlaceField(
                        place: $draft.place, now: now, focus: $focus, searchField: .placeSearch, nameField: .placeName
                    )
                }
            }
            if draft.hasPlace {
                if let place = draft.place, let zone = place.timeZone {
                    Footnote(placeNote(place, zone: zone, moment: moment))
                } else {
                    Footnote("Search by city or time zone. Return picks the highlighted place.")
                }
            }

            GroupedBox {
                CalendarField(
                    title: "Counting from",
                    date: $draft.countingFrom,
                    isOpen: calendarBinding(.countingFrom),
                    focus: $focus,
                    field: .countingFrom,
                    isEnabled: { $0 < draft.moment(on: draft.date) },
                    caption: { countingFromCaption($0, moment: moment) },
                    error: startIsBeforeMoment ? nil : Text("Pick a day before \(shortDay(moment)).")
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
        guard let countdown = draft.countdown else { return }
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
        let days = CountdownMath.calendarDays(from: Date(), to: day, calendar: .local)
        let long = longDay(day)
        switch days {
        case ..<0: return Text("Pick a date in the future.")
        case 0: return Text("\(long) · today")
        case 1: return Text("\(long) · tomorrow")
        default: return Text("\(long) · \(days) days from today")
        }
    }

    /// "Monday, August 3 · 137 days before Fri, Dec 18".
    private func countingFromCaption(_ day: Date, moment: Date) -> Text {
        let days = CountdownMath.calendarDays(from: day, to: moment, calendar: .local)
        guard days > 0 else { return Text("Pick a day before \(shortDay(moment)).") }
        return days == 1
            ? Text("\(longDay(day)) · 1 day before \(shortDay(moment))")
            : Text("\(longDay(day)) · \(days) days before \(shortDay(moment))")
    }

    /// "Date and time are in Tokyo time. 6:40 PM there is 9:40 AM for you." A pinned time is never a surprise.
    private func placeNote(_ place: Place, zone: TimeZone, moment: Date) -> Text {
        let name = place.name.trimmingCharacters(in: .whitespaces).isEmpty ? PlaceSearch.city(of: place.timeZoneID) : place.name
        let local = TimeZone.current
        if CountdownMath.sameOffset(zone, local, at: moment) {
            return Text("Date and time are in \(name) time, the same as yours.")
        }
        let localTime = moment.formatted(Date.FormatStyle(timeZone: local).hour().minute())
        let sameDay = CountdownMath.gregorian(in: zone).dateComponents([.year, .month, .day], from: moment)
            == CountdownMath.gregorian(in: local).dateComponents([.year, .month, .day], from: moment)
        let yours = sameDay ? localTime : "\(localTime) on \(shortDay(moment))"
        guard draft.hasTime else {
            return Text("The date is in \(name) time. It begins at \(yours) for you.")
        }
        let there = moment.formatted(Date.FormatStyle(timeZone: zone).hour().minute())
        return Text("Date and time are in \(name) time. \(there) there is \(yours) for you.")
    }

    private func longDay(_ day: Date) -> String {
        day.formatted(Date.FormatStyle(timeZone: .current).weekday(.wide).month(.wide).day())
    }

    /// "Fri, Dec 18", on the Mac's clock.
    private func shortDay(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(timeZone: .current).weekday(.abbreviated).month(.abbreviated).day())
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
