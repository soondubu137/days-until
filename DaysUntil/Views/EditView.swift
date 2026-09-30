import SwiftUI

/// The edit form's working copy. The pickers edit `Date`s on the Mac's clock; only their day and
/// time components are kept, so a pinned countdown's "6:40 PM" means 6:40 PM at the place.
struct Draft {
    var name = ""
    var icon = CountdownIcon.default
    var date: Date
    var hasTime = false
    var time: Date
    var hasPlace = false
    var place: Place?
    var countingFrom: Date
    var menuBarStyle: MenuBarStyle
    var launchAtLogin: Bool

    /// A blank countdown a month out, counting from today.
    init(menuBarStyle: MenuBarStyle, launchAtLogin: Bool, now: Date = Date()) {
        let calendar = Calendar.local
        let today = calendar.startOfDay(for: now)
        date = calendar.date(byAdding: .month, value: 1, to: today) ?? today
        time = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: today) ?? today
        countingFrom = today
        self.menuBarStyle = menuBarStyle
        self.launchAtLogin = launchAtLogin
    }

    init(editing countdown: Countdown, menuBarStyle: MenuBarStyle, launchAtLogin: Bool) {
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
        self.menuBarStyle = menuBarStyle
        self.launchAtLogin = launchAtLogin
    }

    /// Starts over after a countdown is reached, keeping what's likely to repeat: name, icon and place.
    init(after countdown: Countdown, menuBarStyle: MenuBarStyle, launchAtLogin: Bool) {
        self.init(menuBarStyle: menuBarStyle, launchAtLogin: launchAtLogin)
        name = countdown.name
        icon = countdown.icon
        hasPlace = countdown.place != nil
        place = countdown.place
    }

    /// The countdown the form describes. Nil while it has no name, or a place is switched on but not picked.
    var countdown: Countdown? {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !hasPlace || place != nil else { return nil }
        let local = TimeZone.current
        var place = hasPlace ? place : nil
        if let current = place, current.name.trimmingCharacters(in: .whitespaces).isEmpty {
            place?.name = PlaceSearch.city(of: current.timeZoneID)
        }
        return Countdown(
            name: name,
            icon: icon,
            date: CountdownMath.calendarDay(of: date, in: local),
            time: hasTime ? CountdownMath.timeOfDay(of: time, in: local) : nil,
            place: place,
            countingFrom: CountdownMath.calendarDay(of: countingFrom, in: local)
        )
    }
}

struct EditView: View {
    @Binding var draft: Draft
    let now: Date
    /// Nil on first launch, when there's no countdown to go back to.
    let onCancel: (() -> Void)?
    let onSave: (Countdown) -> Void

    var body: some View {
        let countdown = draft.countdown
        let error = countdown.flatMap { CountdownMath.validate($0, now: now, calendar: .local) }

        VStack(alignment: .leading, spacing: 16) {
            Text(onCancel == nil ? "New Countdown" : "Edit Countdown")
                .font(.headline)

            Form {
                TextField("Name:", text: $draft.name, prompt: Text("Going home"))
                LabeledContent("Icon:") {
                    IconPicker(icon: $draft.icon)
                }
                DatePicker("Date:", selection: $draft.date, displayedComponents: .date)
                LabeledContent("Time:") {
                    HStack {
                        Toggle("Exact time", isOn: $draft.hasTime)
                        if draft.hasTime {
                            DatePicker("Time", selection: $draft.time, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                }
                LabeledContent("Place:") {
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle("Another time zone", isOn: $draft.hasPlace)
                        if draft.hasPlace {
                            PlacePicker(place: $draft.place, now: now)
                            if let place = draft.place {
                                Text("Date and time are in \(placeName(place)) time.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if error == .momentNotInFuture {
                    errorText("Pick a date in the future.")
                }
                DatePicker("Counting from:", selection: $draft.countingFrom, displayedComponents: .date)
                if error == .startNotBeforeMoment {
                    errorText("Start date must be before the countdown date.")
                }
                Picker("Menu bar:", selection: $draft.menuBarStyle) {
                    ForEach(MenuBarStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                Toggle("Launch at login", isOn: $draft.launchAtLogin)
            }

            HStack {
                if let onCancel {
                    Spacer()
                    Button("Cancel", action: onCancel)
                        .keyboardShortcut(.cancelAction)
                } else {
                    Button("Quit Days Until") { NSApplication.shared.terminate(nil) }
                    Spacer()
                }
                Button("Save") {
                    if let countdown { onSave(countdown) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(countdown == nil || error != nil)
            }
        }
        .padding(16)
    }

    private func placeName(_ place: Place) -> String {
        place.name.trimmingCharacters(in: .whitespaces).isEmpty ? PlaceSearch.city(of: place.timeZoneID) : place.name
    }

    private func errorText(_ message: LocalizedStringKey) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }
}

/// The preset symbols, plus a field for any emoji.
private struct IconPicker: View {
    @Binding var icon: CountdownIcon

    var body: some View {
        let symbols = CountdownIcon.presetSymbols
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(symbols.prefix(5), id: \.self, content: symbolButton)
            }
            HStack(spacing: 4) {
                ForEach(symbols.dropFirst(5), id: \.self, content: symbolButton)
                TextField("Emoji", text: emojiBinding, prompt: Text("🙂"))
                    .labelsHidden()
                    .multilineTextAlignment(.center)
                    .frame(width: 30)
                    .help("Type or paste an emoji")
            }
        }
        // Line the "Icon:" label up with the first row.
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.top] + 15 }
    }

    private func symbolButton(_ name: String) -> some View {
        Button {
            icon = .symbol(name)
        } label: {
            Image(systemName: name)
                .frame(width: 26, height: 22)
                .background(icon == .symbol(name) ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Keeps the last character typed; clearing the field goes back to the default icon.
    private var emojiBinding: Binding<String> {
        Binding {
            if case .emoji(let emoji) = icon { emoji } else { "" }
        } set: { text in
            icon = text.last.map { .emoji(String($0)) } ?? .default
        }
    }
}

extension MenuBarStyle {
    var title: LocalizedStringKey {
        switch self {
        case .adaptive: "Adaptive"
        case .daysOnly: "Days only"
        case .daysAndHours: "Days and hours"
        case .alwaysSeconds: "Always show seconds"
        case .iconOnly: "Icon only"
        }
    }
}
