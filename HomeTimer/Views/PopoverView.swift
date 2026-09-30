import Combine
import SwiftUI

/// What the popover shows. The status item owns it, so it outlives the popover's content between
/// openings, and closing the popover can drop an unfinished edit.
final class PopoverState: ObservableObject {
    /// The popover's clocks tick only while it's on screen.
    @Published var isShown = false
    @Published var isEditing: Bool
    /// The edit form's working copy. Kept non-optional, since the form can still read it during the
    /// update that closes the form.
    @Published var draft: Draft

    init(store: CountdownStore) {
        // With nothing to count down to yet, go straight to the form.
        isEditing = store.countdown == nil
        draft = Draft(menuBarStyle: store.menuBarStyle, launchAtLogin: LaunchAtLogin.isEnabled)
    }
}

/// What opens from the menu bar item: the countdown, or the edit form in its place.
struct PopoverView: View {
    @ObservedObject var store: CountdownStore
    @ObservedObject var state: PopoverState
    @State private var now = Date()

    var body: some View {
        Group {
            if let countdown = store.countdown, !state.isEditing {
                SummaryView(countdown: countdown, now: now) {
                    edit(Draft(editing: countdown, menuBarStyle: store.menuBarStyle, launchAtLogin: LaunchAtLogin.isEnabled))
                } onSetNew: {
                    edit(Draft(after: countdown, menuBarStyle: store.menuBarStyle, launchAtLogin: LaunchAtLogin.isEnabled))
                }
            } else {
                EditView(draft: $state.draft, now: now, onCancel: store.countdown == nil ? nil : { state.isEditing = false }) { countdown in
                    save(countdown)
                }
            }
        }
        .frame(width: 340)
        .task(id: state.isShown) {
            while state.isShown, !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(nextTick(after: now).timeIntervalSince(now)))
            }
        }
    }

    private func edit(_ draft: Draft) {
        state.draft = draft
        state.isEditing = true
    }

    private func save(_ countdown: Countdown) {
        store.countdown = countdown
        store.menuBarStyle = state.draft.menuBarStyle
        LaunchAtLogin.set(state.draft.launchAtLogin)
        state.isEditing = false
    }

    /// The next second on the exact line while counting, otherwise the next minute for the place clock.
    private func nextTick(after now: Date) -> Date {
        let minute = 60.0
        let nextMinute = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / minute).rounded(.down) * minute + minute)
        guard !state.isEditing, let countdown = store.countdown else { return nextMinute }
        let moment = CountdownMath.moment(of: countdown, calendar: .local)
        let remaining = moment.timeIntervalSince(now)
        guard remaining > 0 else { return nextMinute }
        return moment - TimeInterval(CountdownMath.wholeUnits(remaining, of: 1))
    }
}

private struct SummaryView: View {
    let countdown: Countdown
    let now: Date
    let onEdit: () -> Void
    let onSetNew: () -> Void

    var body: some View {
        let calendar = Calendar.local
        let moment = CountdownMath.moment(of: countdown, calendar: calendar)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                CountdownIconView(icon: countdown.icon)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(countdown.name)
                    .font(.headline)
                    .lineLimit(1)
            }

            if CountdownMath.phase(of: moment, now: now, calendar: calendar) == .counting {
                counting(moment: moment, calendar: calendar)
            } else {
                reached(moment: moment, calendar: calendar)
            }

            Divider()
            HStack {
                Button("Edit Countdown…", action: onEdit)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private func counting(moment: Date, calendar: Calendar) -> some View {
        let days = CountdownMath.calendarDays(from: now, to: moment, calendar: calendar)

        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if days == 0 {
                    Text("Today").font(.system(size: 40, weight: .semibold, design: .rounded))
                } else {
                    Text("\(days)")
                        .font(.system(size: 44, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(days == 1 ? "day" : "days")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            Text(CountdownMath.exactRemainingText(moment.timeIntervalSince(now)))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }

        if let progress = CountdownMath.progress(
            start: CountdownMath.start(of: countdown, calendar: calendar), moment: moment, now: now
        ) {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                Text("\(Int((progress * 100).rounded(.down)))% of the way")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        let units = CountdownMath.otherUnits(moment: moment, now: now, calendar: calendar)
        HStack(alignment: .top) {
            unit(units.weeks.formatted(.number.precision(.fractionLength(1))), units.weeks == 1 ? "week" : "weeks")
            unit("\(units.weekends)", units.weekends == 1 ? "weekend" : "weekends")
            unit("\(units.workdays)", units.workdays == 1 ? "workday" : "workdays")
        }

        if let place = countdown.place, let zone = place.timeZone {
            Divider()
            placeClock(place, zone: zone, calendar: calendar)
        }
        arrival(moment: moment, calendar: calendar)
    }

    private func unit(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.title3.weight(.medium)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The place's time now, day or night there, and how far ahead or behind it is.
    private func placeClock(_ place: Place, zone: TimeZone, calendar: Calendar) -> some View {
        let time = now.formatted(Date.FormatStyle(timeZone: zone).hour().minute().weekday(.abbreviated))
        let offset = CountdownMath.offsetText(of: zone, from: calendar.timeZone, at: now)
        return HStack(spacing: 8) {
            Image(systemName: CountdownMath.isDaytime(in: zone, at: now) ? "sun.max" : "moon")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(place.name)
            Spacer()
            Text("\(time) · \(offset)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// The moment in full: at the place and on the Mac's clock when pinned, and as a date alone for
    /// a floating date-only countdown.
    @ViewBuilder
    private func arrival(moment: Date, calendar: Calendar) -> some View {
        let local = calendar.timeZone
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                if let place = countdown.place, let zone = place.timeZone {
                    Text("\(fullDate(moment, in: zone, withTime: true)) · \(place.name)")
                    if !CountdownMath.sameOffset(zone, local, at: moment) {
                        Text("\(fullDate(moment, in: local, withTime: true)) · your time")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(fullDate(moment, in: local, withTime: countdown.time != nil))
                }
            }
        }
    }

    private func fullDate(_ date: Date, in zone: TimeZone, withTime: Bool) -> String {
        let style = Date.FormatStyle(timeZone: zone).weekday(.abbreviated).month(.abbreviated).day().year()
        return date.formatted(withTime ? style.hour().minute() : style)
    }

    /// "Reached Dec 19 · 3 days ago". It never counts negative.
    @ViewBuilder
    private func reached(moment: Date, calendar: Calendar) -> some View {
        let day = moment.formatted(Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day())
        let daysSince = CountdownMath.calendarDays(from: moment, to: now, calendar: calendar)

        Label("Reached \(day) · \(Self.daysAgo(daysSince))", systemImage: "checkmark.circle")
            .font(.title3)
        Button("Set New Countdown", action: onSetNew)
            .buttonStyle(.borderedProminent)
    }

    /// "today", "yesterday", "3 days ago".
    private static func daysAgo(_ days: Int) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(from: DateComponents(day: -days))
    }
}

private struct CountdownIconView: View {
    let icon: CountdownIcon

    var body: some View {
        switch icon {
        case .symbol(let name): Image(systemName: name)
        case .emoji(let emoji): Text(emoji)
        }
    }
}
