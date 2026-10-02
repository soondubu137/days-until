import SwiftUI

/// The popover while a countdown is set: counting, the day itself, and after it.
struct CountdownView: View {
    let countdown: Countdown
    let now: Date
    /// Builds the ••• menu each time it opens.
    let makeMenu: () -> NSMenu
    let onStartOver: () -> Void

    var body: some View {
        let calendar = Calendar.local
        let moment = CountdownMath.moment(of: countdown, calendar: calendar)
        let start = CountdownMath.start(of: countdown, calendar: calendar)
        let readout = CountdownMath.readout(moment: moment, now: now, calendar: calendar)
        let runway = CountdownMath.runway(start: start, moment: moment, now: now, calendar: calendar)

        VStack(alignment: .leading, spacing: 16) {
            header(isFinal: readout.isFinal)

            switch readout {
            case .days, .daysAndHours, .clock:
                hero(readout, moment: moment, calendar: calendar)
                progress(runway, start: start, moment: moment, readout: readout, calendar: calendar)
                if case .clock = readout {} else {
                    stats(moment: moment, calendar: calendar)
                }
                details(moment: moment, calendar: calendar, showsArrival: true)

            case .today:
                VStack(alignment: .leading, spacing: 0) {
                    Text("Today")
                        .font(.count)
                        .foregroundStyle(Color.accentColor)
                    reachedLine(moment: moment, calendar: calendar)
                        .foregroundStyle(.secondary)
                }
                progress(runway, start: start, moment: moment, readout: readout, calendar: calendar)
                details(moment: moment, calendar: calendar, showsArrival: false)

            case .past(let daysSince):
                past(daysSince: daysSince, moment: moment, runway: runway, start: start, calendar: calendar)
            }
        }
        .padding(16)
    }

    // MARK: - Header

    private func header(isFinal: Bool) -> some View {
        HStack(spacing: 9) {
            CountdownIconView(icon: countdown.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isFinal ? Color.white : Color.accentColor)
                .frame(width: 26, height: 26)
                .background(
                    isFinal ? Color.accentColor : Color.accentSoft,
                    in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                )
                .accessibilityHidden(true)
            Text(countdown.name)
                .font(.headline)
                .lineLimit(1)
            Spacer(minLength: 8)
            MoreButton(makeMenu: makeMenu)
        }
    }

    // MARK: - Counting

    /// The count, following the same ladder as the menu bar, with a line under it: the exact time
    /// left, or the date itself for a countdown without a time.
    @ViewBuilder
    private func hero(_ readout: CountdownMath.Readout, moment: Date, calendar: Calendar) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            switch readout {
            case .days(let days):
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    count(days, unit: days == 1 ? "day" : "days")
                }
            case .daysAndHours(let days, let hours):
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    count(days, unit: days == 1 ? "day" : "days")
                    count(hours, unit: hours == 1 ? "hour" : "hours")
                        .padding(.leading, 11)
                }
            case .clock(let clock):
                Text(clock)
                    .font(.count)
                    .monospacedDigit()
                    .foregroundStyle(Color.accentColor)
                    .padding(.bottom, 2)
            case .today, .past:
                EmptyView()
            }

            Group {
                if !countdown.showsTime {
                    Text(longDate(of: countdown))
                } else if case .clock = readout {
                    Text(CountdownMath.untilText(moment: moment, now: now, calendar: calendar))
                } else {
                    Text(CountdownMath.exactRemainingText(moment.timeIntervalSince(now)))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private func count(_ number: Int, unit: LocalizedStringKey) -> some View {
        Group {
            Text("\(number)")
                .font(.count)
                .monospacedDigit()
            Text(unit)
                .font(.countUnit)
                .foregroundStyle(.secondary)
        }
    }

    /// The runway and what it shows: how far along, and what the ticks count.
    private func progress(
        _ runway: CountdownMath.Runway, start: Date, moment: Date, readout: CountdownMath.Readout, calendar: Calendar
    ) -> some View {
        let from = start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day())
        let percent = CountdownMath.progress(start: start, moment: moment, now: now).map { Int(($0 * 100).rounded(.down)) } ?? 0
        let (leading, trailing): (String, String) =
            switch (readout, runway.scale) {
            case (.today, _), (.past, _):
                (String(localized: "All the way"), String(localized: "\(runway.days) days from \(from)"))
            case (_, .hours):
                (String(localized: "Final 24 hours"), String(localized: "One tick an hour"))
            case (_, .weeks):
                (
                    String(localized: "\(percent)% of the way"),
                    String(localized: "One tick a week · from \(start.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day()))")
                )
            case (_, .days):
                (String(localized: "\(percent)% of the way"), String(localized: "Counting from \(from)"))
            }

        return VStack(alignment: .leading, spacing: 8) {
            RunwayView(runway: runway, icon: countdown.icon, isLit: readout == .today, isPast: readout.isPast)
            HStack {
                Text(leading)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(trailing)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private func stats(moment: Date, calendar: Calendar) -> some View {
        let units = CountdownMath.otherUnits(moment: moment, now: now, calendar: calendar)
        return HStack(alignment: .top, spacing: 0) {
            stat(units.weeks.formatted(.number.precision(.fractionLength(1))), units.weeks == 1 ? "week" : "weeks")
            stat("\(units.weekends)", units.weekends == 1 ? "weekend" : "weekends")
            stat("\(units.weekdays)", units.weekdays == 1 ? "weekday" : "weekdays")
                .help("Monday through Friday, including today and excluding the target date. Holidays are not excluded.")
        }
    }

    private func stat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value)
                .font(.stat)
                .monospacedDigit()
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - When and where

    /// The fixed moment in local time first, then the auxiliary zone, and the place's clock now.
    /// A date-only target needs no box only while it is still local midnight and no place is set.
    @ViewBuilder
    private func details(moment: Date, calendar: Calendar, showsArrival: Bool) -> some View {
        let zone = countdown.place?.timeZone
        let arrival = showsArrival && (zone != nil || countdown.showsTime || calendar.startOfDay(for: moment) != moment)
        if arrival || zone != nil {
            GroupedBox {
                if arrival {
                    arrivalRow(moment: moment, calendar: calendar)
                }
                if let place = countdown.place, let zone {
                    if arrival {
                        RowDivider(inset: 36)
                    }
                    placeClockRow(place, zone: zone, calendar: calendar)
                }
            }
        }
    }

    private func arrivalRow(moment: Date, calendar: Calendar) -> some View {
        let local = calendar.timeZone
        return detailRow(systemImage: "calendar") {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(shortDate(moment, in: local, withTime: true))
                    Spacer()
                    Text("Your time").foregroundStyle(.secondary)
                }
                if let place = countdown.place, let zone = place.timeZone {
                    HStack {
                        Text(shortDate(moment, in: zone, withTime: true))
                        Spacer()
                        Text(place.name)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// The place's time now, day or night there, and how far ahead or behind it is.
    private func placeClockRow(_ place: Place, zone: TimeZone, calendar: Calendar) -> some View {
        let time = now.formatted(Date.FormatStyle(timeZone: zone).hour().minute().weekday(.abbreviated))
        let offset = CountdownMath.offsetText(of: zone, from: calendar.timeZone, at: now)
        return detailRow(systemImage: CountdownMath.isDaytime(in: zone, at: now) ? "sun.max" : "moon") {
            HStack {
                Text(place.name)
                Spacer()
                Text("\(time) · \(offset)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func detailRow<Content: View>(systemImage: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            content()
        }
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The day and after

    /// "Reached at 9:40 AM · 6:40 PM in Tokyo", or the date itself for a countdown without a time.
    private func reachedLine(moment: Date, calendar: Calendar) -> Text {
        if let place = countdown.place, let zone = place.timeZone {
            return Text("Reached \(shortDate(moment, in: calendar.timeZone, withTime: true)) · \(shortDate(moment, in: zone, withTime: true)) in \(place.name)")
        }
        return Text("Reached \(shortDate(moment, in: calendar.timeZone, withTime: countdown.showsTime || calendar.startOfDay(for: moment) != moment))")
    }

    /// "Reached Fri, Dec 18 · 3 days ago", the runway run out, and one clear next step.
    @ViewBuilder
    private func past(daysSince: Int, moment: Date, runway: CountdownMath.Runway, start: Date, calendar: Calendar) -> some View {
        let day = moment.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).month(.abbreviated).day())
        VStack(alignment: .leading, spacing: 4) {
            Text("Reached \(day)")
                .font(.title)
            Text(Self.daysAgo(daysSince))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        progress(runway, start: start, moment: moment, readout: .past(daysSince: daysSince), calendar: calendar)
        VStack(spacing: 8) {
            Button(action: onStartOver) {
                Text("Set New Countdown…")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            Text(countdown.place == nil ? "Keeps the name and icon." : "Keeps the name, icon and place.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// "Yesterday", "3 days ago".
    private static func daysAgo(_ days: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        formatter.formattingContext = .beginningOfSentence
        return formatter.localizedString(from: DateComponents(day: -days))
    }

    // MARK: - Dates

    /// "Saturday, April 24, 2027": the countdown's day as it reads where it's counted.
    private func longDate(of countdown: Countdown) -> String {
        let moment = countdown.targetDate
        let withTime = Calendar.local.startOfDay(for: moment) != moment
        return moment.formatted(Date.FormatStyle(date: .complete, time: withTime ? .shortened : .omitted,
                                                calendar: Calendar.local, timeZone: .current))
    }

    /// "Fri, Dec 18 · 6:40 PM".
    private func shortDate(_ date: Date, in zone: TimeZone, withTime: Bool) -> String {
        let day = date.formatted(Date.FormatStyle(timeZone: zone).year().weekday(.abbreviated).month(.abbreviated).day())
        guard withTime else { return day }
        return "\(day) · \(date.formatted(Date.FormatStyle(timeZone: zone).hour().minute()))"
    }
}

private extension CountdownMath.Readout {
    /// The final 24 hours and the day itself, when colour comes in.
    var isFinal: Bool {
        switch self {
        case .clock, .today: true
        case .days, .daysAndHours, .past: false
        }
    }

    var isPast: Bool {
        if case .past = self { true } else { false }
    }
}

/// The ••• button. The menu is AppKit's, so it looks and behaves like any Mac menu, with key
/// equivalents and a live preview beside each menu bar style.
struct MoreButton: View {
    let makeMenu: () -> NSMenu

    var body: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Color.well, in: Circle())
            .overlay(MenuAnchor(makeMenu: makeMenu))
    }
}

/// Opens the menu under the button on mouse down, as pop-up menus do.
private struct MenuAnchor: NSViewRepresentable {
    let makeMenu: () -> NSMenu

    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.makeMenu = makeMenu
    }

    final class AnchorView: NSView {
        var makeMenu: (() -> NSMenu)?

        override func mouseDown(with event: NSEvent) {
            showMenu()
        }

        private func showMenu() {
            guard let menu = makeMenu?() else { return }
            // Right edges lined up, the menu just below the button.
            menu.popUp(positioning: nil, at: NSPoint(x: bounds.width - menu.size.width, y: -4), in: self)
        }

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .menuButton }
        override func accessibilityLabel() -> String? { String(localized: "More") }
        override func accessibilityPerformPress() -> Bool {
            showMenu()
            return true
        }
    }
}
