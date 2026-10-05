import SwiftUI
import WidgetKit

/// Every state keeps the same rows in the same order: the name, the readout, the runway, then one
/// line in Small. Medium sets the date beside the readout, and says what the runway shows under it.
/// Large has the popover's runway, month names included, and the other ways to count. Closer, the
/// readout climbs the popover's ladder; the runway stays.
struct CountdownWidgetView: View {
    let entry: CountdownEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let countdown = entry.countdown {
                CountingWidget(countdown: countdown, now: entry.date, family: family)
            } else {
                EmptyWidget()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct CountingWidget: View {
    let countdown: Countdown
    let now: Date
    let family: WidgetFamily

    private var calendar: Calendar { .local }
    private var moment: Date { countdown.targetDate }
    private var isSmall: Bool { family == .systemSmall }
    private var isLarge: Bool { family == .systemLarge }

    var body: some View {
        let readout = CountdownMath.readout(moment: moment, now: now, calendar: calendar)
        if isLarge {
            large(readout)
        } else {
            compact(readout)
        }
    }

    private func compact(_ readout: CountdownMath.Readout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(icon: countdown.icon, name: Text(countdown.name))
            Spacer(minLength: 4)
            if isSmall {
                headline(readout)
            } else {
                HStack(spacing: 12) {
                    headline(readout)
                    Spacer(minLength: 0)
                    detail(readout)
                }
            }
            Spacer(minLength: 4)
            runway(readout, style: isSmall ? .small : .medium)
            if isSmall {
                Spacer(minLength: 4)
                Text(line(readout))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                caption(readout)
                    .padding(.top, 6)
            }
        }
    }

    /// The readout and its line at the top, and what there's room for below: the runway with its
    /// month names, the other ways to count while counting, and the arrival in both zones when a
    /// place is set. Without one, the line under the readout already says when.
    private func large(_ readout: CountdownMath.Readout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(icon: countdown.icon, name: Text(countdown.name))
            VStack(alignment: .leading, spacing: 2) {
                headline(readout)
                Text(longLine(readout))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.top, 20)
            Spacer(minLength: 12)
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    runway(readout, style: .large)
                    caption(readout)
                }
                switch readout {
                case .days, .daysAndHours: stats
                case .clock, .today, .past: EmptyView()
                }
                if !readout.isReached, let place = countdown.place, let zone = place.timeZone {
                    arrival(place: place, zone: zone)
                }
            }
        }
    }

    // MARK: - Readout

    /// Days, then days and hours, then the seconds clock, as in the menu bar. The clock is the
    /// system's, so it keeps time between the timeline's entries.
    @ViewBuilder
    private func headline(_ readout: CountdownMath.Readout) -> some View {
        switch readout {
        case .days(let days):
            // For large counts the number shrinks before the unit would be cut short.
            let parts = NumberPhrase(
                String(localized: "\(days) days", comment: "The number is set large, the words beside it small."),
                number: days.formatted()
            )
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if !parts.before.isEmpty {
                    unit(parts.before)
                }
                Text(parts.number)
                    .font(.readout(isLarge ? 64 : 52))
                    .monospacedDigit()
                    .minimumScaleFactor(0.5)
                if !parts.after.isEmpty {
                    unit(parts.after)
                }
            }
            .lineLimit(1)
        case .daysAndHours(let days, let hours):
            Text(String(localized: "\(days)d \(hours)h", comment: "Days and hours, as short as possible."))
                .font(.readout(readoutSize(small: 37)))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        case .clock:
            Text(timerInterval: now...moment, countsDown: true, showsHours: true)
                .font(.readout(readoutSize(small: 34)))
                .monospacedDigit()
                .foregroundStyle(Color.accentColor)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        case .today:
            Text("Today")
                .font(.readout(readoutSize(small: 37)))
                .foregroundStyle(Color.accentColor)
                .widgetAccentable()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        case .past:
            Text("Reached", comment: "The countdown's day has been and gone. Set large, in place of the days left.")
                .font(.readout(readoutSize(small: 32)))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    /// Small sets the longer readouts smaller than its days, so they fit.
    private func readoutSize(small: CGFloat) -> CGFloat {
        isSmall ? small : isLarge ? 64 : 52
    }

    private func unit(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .fixedSize()
    }

    // MARK: - When

    /// Small's line: the day, its time too in the final week, then what the popover says under the
    /// clock and Today, and how long ago after the day.
    func line(_ readout: CountdownMath.Readout) -> String {
        switch readout {
        case .days: day
        case .daysAndHours: dayAndTime
        case .clock: CountdownMath.untilText(moment: moment, now: now, calendar: calendar)
        case .today: CountdownMath.reachedText(moment: moment, showsTime: countdown.showsTime, place: countdown.place, calendar: calendar)
        case .past(let days): "\(day) · \(Self.daysAgo(days))"
        }
    }

    /// Large's line: the day in full, with its time when it has one, then as Small's.
    func longLine(_ readout: CountdownMath.Readout) -> String {
        let withTime = countdown.showsTime || calendar.startOfDay(for: moment) != moment
        let date = moment.formatted(Date.FormatStyle(date: .complete, time: withTime ? .shortened : .omitted,
                                                     calendar: calendar, timeZone: calendar.timeZone))
        switch readout {
        case .days, .daysAndHours: return date
        case .clock, .today: return line(readout)
        case .past(let days):
            let day = moment.formatted(Date.FormatStyle(date: .complete, time: .omitted, calendar: calendar, timeZone: calendar.timeZone))
            return "\(day) · \(Self.daysAgo(days))"
        }
    }

    /// Medium's date beside the readout, with the weekends left under it while counting.
    func detailLines(_ readout: CountdownMath.Readout) -> (top: String, bottom: String?) {
        switch readout {
        case .days:
            (day, weekendsLeft)
        case .daysAndHours:
            (dayAndTime, weekendsLeft)
        case .clock:
            (String(localized: "Until \(time)"), relativeDay)
        case .today:
            (day, CountdownMath.reachedText(moment: moment, showsTime: countdown.showsTime, place: countdown.place, calendar: calendar))
        case .past(let days):
            (day, Self.daysAgo(days))
        }
    }

    private func detail(_ readout: CountdownMath.Readout) -> some View {
        let (top, bottom) = detailLines(readout)
        return VStack(alignment: .trailing, spacing: 2) {
            Text(top)
                .font(.system(size: 13, weight: .semibold))
            if let bottom {
                Text(bottom)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .layoutPriority(1)
    }

    /// "Fri, Dec 18".
    private var day: String {
        moment.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day())
    }

    /// "9:40 AM".
    private var time: String {
        moment.formatted(Date.FormatStyle(timeZone: calendar.timeZone).hour().minute())
    }

    /// "Fri, Dec 18 · 9:40 AM": in the final week the time counts too, when there is one.
    private var dayAndTime: String {
        countdown.showsTime || calendar.startOfDay(for: moment) != moment ? "\(day) · \(time)" : day
    }

    private var weekendsLeft: String? {
        let weekends = CountdownMath.otherUnits(moment: moment, now: now, calendar: calendar).weekends
        guard weekends > 0 else { return nil }
        return String(localized: "\(weekends) weekends left", comment: "Saturdays from today until the day, under it in the Medium widget.")
    }

    /// "tomorrow", under "Until 9:40 AM", or the day itself when spring-forward makes it further.
    private var relativeDay: String {
        let days = CountdownMath.calendarDays(from: now, to: moment, calendar: calendar)
        guard days <= 1 else { return day }
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .middleOfSentence
        return formatter.localizedString(from: DateComponents(day: days))
    }

    /// "Yesterday", "3 days ago".
    private static func daysAgo(_ days: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .standalone
        return formatter.localizedString(from: DateComponents(day: -days))
    }

    // MARK: - Runway

    private func runway(_ readout: CountdownMath.Readout, style: WidgetRunway.Style) -> some View {
        WidgetRunway(
            style: style, start: countdown.startDate, moment: moment, now: now,
            icon: countdown.icon, isLit: readout == .today, isPast: readout.isPast
        )
    }

    /// Medium's and Large's line under the runway, as the popover's.
    func captionLines(_ readout: CountdownMath.Readout) -> (leading: String, trailing: String?) {
        let start = countdown.startDate
        let from = start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day())
        let percent = CountdownMath.progress(start: start, moment: moment, now: now).map { Int(($0 * 100).rounded(.down)) } ?? 0
        switch readout {
        case .today, .past:
            return (
                String(localized: "All the way"),
                String(localized: "\(CountdownMath.calendarDays(from: start, to: moment, calendar: calendar)) days from \(from)")
            )
        case .clock:
            return (String(localized: "Final 24 hours"), nil)
        case .days, .daysAndHours:
            return (String(localized: "\(percent)% of the way"), String(localized: "Counting from \(from)"))
        }
    }

    private func caption(_ readout: CountdownMath.Readout) -> some View {
        let (leading, trailing) = captionLines(readout)
        return HStack {
            Text(leading)
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    // MARK: - Large

    /// Weeks, weekends and weekdays, as the popover counts them, spread across the width.
    private var stats: some View {
        let units = CountdownMath.otherUnits(moment: moment, now: now, calendar: calendar)
        let weeks = units.weeks.formatted(.number.precision(.fractionLength(1)))
        return HStack(alignment: .top, spacing: 0) {
            stat(String(localized: "\(weeks) weeks", comment: "The number is set large, the words under it as a label."), number: weeks)
            Spacer(minLength: 12)
            stat(String(localized: "\(units.weekends) weekends", comment: "The number is set large, the words under it as a label."),
                 number: units.weekends.formatted())
            Spacer(minLength: 12)
            stat(String(localized: "\(units.weekdays) weekdays", comment: "The number is set large, the words under it as a label."),
                 number: units.weekdays.formatted())
        }
    }

    private func stat(_ phrase: String, number: String) -> some View {
        let parts = NumberPhrase(phrase, number: number)
        return VStack(alignment: .leading, spacing: 1) {
            Text(parts.number)
                .font(.readout(20))
                .monospacedDigit()
            Text([parts.before, parts.after].filter { !$0.isEmpty }.joined(separator: " "))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
    }

    /// "Your time" first, then the place, each with its date and year, as in the popover.
    private func arrival(place: Place, zone: TimeZone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle()
                .fill(Color.hairline)
                .frame(height: 1)
            arrivalRow(Text("Your time"), in: calendar.timeZone)
            arrivalRow(Text(place.name), in: zone)
        }
        .font(.system(size: 12))
        .lineLimit(1)
    }

    private func arrivalRow(_ label: Text, in zone: TimeZone) -> some View {
        let day = moment.formatted(Date.FormatStyle(timeZone: zone).year().weekday(.abbreviated).month(.abbreviated).day())
        return HStack {
            label
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(verbatim: "\(day) · \(moment.formatted(Date.FormatStyle(timeZone: zone).hour().minute()))")
        }
    }
}

/// No countdown yet: the calendar icon and "Set date", as in the menu bar.
struct EmptyWidget: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetHeader(icon: .symbol("calendar"), name: Text("Days Until"))
            Spacer(minLength: 4)
            Text("Your next big day.", comment: "In the desktop widget while no countdown is set.")
                .font(.system(size: 15, weight: .medium))
            Spacer(minLength: 4)
            Text("Set date")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .widgetAccentable()
        }
    }
}

/// The countdown's icon in the accent colour, and its name on one line.
private struct WidgetHeader: View {
    let icon: CountdownIcon
    let name: Text

    var body: some View {
        HStack(spacing: 7) {
            CountdownIconView(icon: icon)
                .symbolVariant(.fill)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18, height: 18)
                // An emoji keeps its own colours.
                .widgetAccentable(icon.emoji == nil)
            name
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)
        }
    }
}

private extension Font {
    /// The readout: days left, days and hours, the clock, Today.
    static func readout(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }
}

private extension CountdownMath.Readout {
    var isPast: Bool {
        if case .past = self { true } else { false }
    }

    /// The day itself, or after it.
    var isReached: Bool {
        switch self {
        case .today, .past: true
        case .days, .daysAndHours, .clock: false
        }
    }
}
