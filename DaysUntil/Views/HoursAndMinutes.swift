import SwiftUI

/// Our own hours and minutes, under the time field, so a time can be set without the keyboard: an
/// hour, then a minute. They're drawn like the calendar and numbered as the field writes them, and
/// the field still takes typing for any minute that isn't on show.
struct HoursAndMinutes: View {
    @Binding var time: TimeOfDay
    let close: () -> Void
    var labels = TimeLabels(locale: .autoupdatingCurrent)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header("Hour") {
                if labels.isTwelveHour {
                    Picker(selection: isAfternoon) {
                        Text(verbatim: labels.amSymbol).tag(false)
                        Text(verbatim: labels.pmSymbol).tag(true)
                    } label: {
                        Text(verbatim: "\(labels.amSymbol) / \(labels.pmSymbol)")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .focusable(false)
                }
            }
            grid(labels.hours(around: time.hour)) { hour in
                ChoiceCell(label: labels.label(hour: hour), spoken: labels.spoken(hour: hour), isSelected: hour == time.hour) {
                    time.hour = hour
                }
            }
            header("Minute") { EmptyView() }
            grid(TimeLabels.minutes) { minute in
                ChoiceCell(label: labels.label(minute: minute), spoken: labels.spoken(minute: minute), isSelected: minute == time.minute) {
                    time.minute = minute
                    close()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 12)
        .onKeyDown { event in
            // Return and Esc close them, never saving or cancelling the form.
            guard event.key == .returnKey || event.key == .escape else { return false }
            close()
            return true
        }
    }

    /// AM and PM switch the half of the day and keep the hour.
    private var isAfternoon: Binding<Bool> {
        Binding { time.hour >= 12 } set: { time.hour = time.hour % 12 + ($0 ? 12 : 0) }
    }

    private func header<Accessory: View>(_ title: LocalizedStringKey, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title)
                .font(.micro)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            accessory()
        }
        .frame(height: 24)
    }

    /// Rows of six.
    private func grid<Cell: View>(_ values: [Int], @ViewBuilder cell: @escaping (Int) -> Cell) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<values.count / 6, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(values[row * 6..<row * 6 + 6], id: \.self) { value in
                        cell(value).frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }
}

/// An hour or a minute, drawn like a day in the calendar: the chosen one is a filled accent circle,
/// and hover a quiet well.
private struct ChoiceCell: View {
    let label: String
    let spoken: String
    let isSelected: Bool
    let pick: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: pick) {
            Text(verbatim: label)
                .font(isSelected ? .body.weight(.semibold) : .body)
                .monospacedDigit()
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor : isHovered ? Color.well : Color.clear, in: Circle())
                .frame(maxWidth: .infinity)
                .frame(height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(verbatim: spoken))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The Mac's clock: 12- or 24-hour as System Settings says, and the hours numbered as the time
/// field numbers them.
struct TimeLabels {
    let locale: Locale

    /// Every five minutes.
    static let minutes = Array(stride(from: 0, to: 60, by: 5))

    var isTwelveHour: Bool {
        locale.hourCycle == .oneToTwelve || locale.hourCycle == .zeroToEleven
    }

    /// The half of the day `hour` is in on a 12-hour clock, midnight or noon first, or all 24.
    func hours(around hour: Int) -> [Int] {
        guard isTwelveHour else { return Array(0..<24) }
        return hour < 12 ? Array(0..<12) : Array(12..<24)
    }

    /// "9", "09", or "12" for midnight: the digits the field writes before the minutes. The hour
    /// alone can be written differently, like "0时" in Chinese where the field has "09:40".
    func label(hour: Int) -> String {
        let time = moment(hour: hour, minute: 0).formatted(style.hour().minute())
        return String(time.drop { !$0.isNumber }.prefix { $0.isNumber })
    }

    func label(minute: Int) -> String {
        minute.formatted(.number.locale(locale).grouping(.never).precision(.integerLength(2)))
    }

    /// What VoiceOver says: "9 AM", "40 minutes".
    func spoken(hour: Int) -> String {
        moment(hour: hour, minute: 0).formatted(style.hour())
    }

    func spoken(minute: Int) -> String {
        Duration.seconds(minute * 60).formatted(.units(allowed: [.minutes], width: .wide).locale(locale))
    }

    var amSymbol: String { calendar.amSymbol }
    var pmSymbol: String { calendar.pmSymbol }

    private var calendar: Calendar {
        var calendar = Calendar.editor
        calendar.locale = locale
        return calendar
    }

    private var style: Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: .editor, timeZone: .gmt)
    }

    private func moment(hour: Int, minute: Int) -> Date {
        CountdownMath.date(CalendarDay(year: 2001, month: 1, day: 1), at: TimeOfDay(hour: hour, minute: minute), in: .gmt)
    }
}
