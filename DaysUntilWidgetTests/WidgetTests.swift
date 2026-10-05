import SwiftUI
import Testing
import WidgetKit

// The widget's own code, built into this bundle with the model it shares with the app, since the
// extension itself can't be loaded by tests. There's no app here, so strings are the catalog's
// English keys, without plurals.

/// Defaults that live only in memory, so no test touches the widget's real shared domain.
nonisolated final class MemoryDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]

    init() {
        super.init(suiteName: "DaysUntilWidgetTests.Memory")!
    }

    override func data(forKey key: String) -> Data? { values[key] as? Data }
    override func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// A view as SwiftUI draws it, off screen, at 1x.
func render<V: View>(_ view: V, width: CGFloat, height: CGFloat? = nil) -> CGImage? {
    let renderer = ImageRenderer(content: view.frame(width: width, height: height))
    renderer.scale = 1
    return renderer.cgImage
}

/// How many pixels a drawing covers at all.
func ink(_ image: CGImage?) -> Int {
    guard let image else { return 0 }
    var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
    pixels.withUnsafeMutableBytes { buffer in
        CGContext(
            data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }
    return stride(from: 3, to: pixels.count, by: 4).count { pixels[$0] > 0 }
}

/// Wall-clock times on the Mac's own calendar, as the widget reads them.
private func local(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    Calendar.local.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
}

/// Mon, Aug 3 to Fri, Dec 18, 2026 at 9:40 AM, as in the designs.
private let start = local(2026, 8, 3)
private let moment = local(2026, 12, 18, 9, 40)
private let tokyo = Place(timeZoneID: "Asia/Tokyo", name: "Tokyo")

private func countdown(showsTime: Bool = true, place: Place? = nil, icon: CountdownIcon = .default) -> Countdown {
    Countdown(name: "Going home", icon: icon, targetDate: showsTime ? moment : local(2026, 12, 18),
              showsTime: showsTime, place: place, startDate: start)
}

/// Each step of the readout's ladder.
private enum Step: CaseIterable {
    case days, finalWeek, finalDay, today, after

    var now: Date {
        switch self {
        case .days: local(2026, 10, 4, 10)
        case .finalWeek: local(2026, 12, 12, 17, 30)
        case .finalDay: local(2026, 12, 17, 19, 57, 53)
        case .today: local(2026, 12, 18, 12)
        case .after: local(2026, 12, 21, 12)
        }
    }

    func readout(_ countdown: Countdown) -> CountdownMath.Readout {
        CountdownMath.readout(moment: countdown.targetDate, now: now, calendar: .local)
    }
}

private let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]

private func size(of family: WidgetFamily) -> CGSize {
    switch family {
    case .systemSmall: CGSize(width: 138, height: 138)
    case .systemMedium: CGSize(width: 328, height: 138)
    default: CGSize(width: 328, height: 344)
    }
}

// MARK: - Timeline

struct ProviderTests {
    let defaults = MemoryDefaults()

    private func share(_ countdown: Countdown) throws {
        defaults.set(try JSONEncoder().encode(countdown), forKey: WidgetShare.countdownKey)
    }

    @Test func withoutACountdownTheWidgetWaitsForTheApp() {
        let now = Step.days.now
        let timeline = CountdownProvider(defaults: defaults).timeline(now: now)
        #expect(timeline.entries.map(\.date) == [now])
        #expect(timeline.entries.first?.countdown == nil)
        #expect(timeline.policy == .never)
    }

    @Test func anEntryForEachChangeThenAFreshTimeline() throws {
        let countdown = countdown(place: tokyo)
        try share(countdown)
        let now = Step.days.now
        let timeline = CountdownProvider(defaults: defaults).timeline(now: now)
        #expect(timeline.entries.first?.date == now)
        #expect(Array(timeline.entries.dropFirst().map(\.date))
            == CountdownMath.widgetUpdates(moment: moment, now: now, calendar: .local, limit: CountdownProvider.entryLimit))
        #expect(timeline.entries.allSatisfy { $0.countdown == countdown })
        #expect(timeline.policy == .atEnd)
    }

    @Test func unreadableDataIsNoCountdown() {
        defaults.set(Data("not a countdown".utf8), forKey: WidgetShare.countdownKey)
        #expect(CountdownProvider(defaults: defaults).savedCountdown() == nil)
    }
}

// MARK: - What it says

struct WidgetTextTests {
    let day = moment.formatted(Date.FormatStyle(timeZone: .current).weekday(.abbreviated).month(.abbreviated).day())
    let time = moment.formatted(Date.FormatStyle(timeZone: .current).hour().minute())
    let from = start.formatted(Date.FormatStyle(timeZone: .current).weekday(.abbreviated).month(.abbreviated).day())

    private func widget(_ countdown: Countdown, _ step: Step, _ family: WidgetFamily = .systemSmall) -> CountingWidget {
        CountingWidget(countdown: countdown, now: step.now, family: family)
    }

    private func line(_ countdown: Countdown, _ step: Step) -> String {
        widget(countdown, step).line(step.readout(countdown))
    }

    @Test func smallsLineGivesTheDayThenWhatThePopoverSays() {
        let timed = countdown()
        #expect(line(timed, .days) == day)
        // In the final week the time counts too, when there is one.
        #expect(line(timed, .finalWeek) == "\(day) · \(time)")
        #expect(line(countdown(showsTime: false), .finalWeek) == day)
        #expect(line(timed, .finalDay) == CountdownMath.untilText(moment: moment, now: Step.finalDay.now, calendar: .local))
        #expect(line(timed, .today) == CountdownMath.reachedText(moment: moment, showsTime: true, place: nil, calendar: .local))
        #expect(line(timed, .after) == "\(day) · 3 days ago")
    }

    @Test func largesLineGivesTheDayInFull() {
        let full = Date.FormatStyle(date: .complete, time: .omitted, calendar: .local, timeZone: .current)
        let timed = countdown()
        #expect(widget(timed, .days).longLine(.days(75)) == moment.formatted(
            Date.FormatStyle(date: .complete, time: .shortened, calendar: .local, timeZone: .current)))
        let dateOnly = countdown(showsTime: false)
        #expect(widget(dateOnly, .finalWeek).longLine(Step.finalWeek.readout(dateOnly)) == dateOnly.targetDate.formatted(full))
        #expect(widget(timed, .finalDay).longLine(Step.finalDay.readout(timed)) == line(timed, .finalDay))
        #expect(widget(timed, .today).longLine(.today) == line(timed, .today))
        #expect(widget(timed, .after).longLine(.past(daysSince: 3)) == "\(moment.formatted(full)) · 3 days ago")
    }

    @Test func mediumSetsTheDayBesideTheReadout() {
        let timed = countdown()
        let weekends = CountdownMath.otherUnits(moment: moment, now: Step.days.now, calendar: .local).weekends
        #expect(widget(timed, .days, .systemMedium).detailLines(.days(75)) == (day, "\(weekends) weekends left"))
        let finalWeek = widget(timed, .finalWeek, .systemMedium).detailLines(Step.finalWeek.readout(timed))
        #expect(finalWeek.top == "\(day) · \(time)")
        // Sat, Dec 12 still has a weekend to go.
        #expect(finalWeek.bottom != nil)
        // From Sun, Dec 13 there's none, so the line goes.
        let sunday = CountingWidget(countdown: timed, now: local(2026, 12, 13, 10), family: .systemMedium)
        #expect(sunday.detailLines(.daysAndHours(days: 4, hours: 23)).bottom == nil)
        #expect(widget(timed, .finalDay, .systemMedium).detailLines(Step.finalDay.readout(timed)) == ("Until \(time)", "tomorrow"))
        #expect(widget(timed, .today, .systemMedium).detailLines(.today)
            == (day, CountdownMath.reachedText(moment: moment, showsTime: true, place: nil, calendar: .local)))
        #expect(widget(timed, .after, .systemMedium).detailLines(.past(daysSince: 3)) == (day, "3 days ago"))
    }

    @Test func underTheRunwayAsInThePopover() {
        let timed = countdown()
        let counting = widget(timed, .days, .systemMedium).captionLines(.days(75))
        #expect(counting.leading.hasSuffix("% of the way"))
        #expect(counting.trailing == "Counting from \(from)")
        #expect(widget(timed, .finalDay, .systemMedium).captionLines(Step.finalDay.readout(timed)) == ("Final 24 hours", nil))
        for step in [Step.today, .after] {
            #expect(widget(timed, step, .systemLarge).captionLines(step.readout(timed)) == ("All the way", "137 days from \(from)"))
        }
    }
}

// MARK: - How it looks

@Suite @MainActor
struct WidgetRenderTests {
    @Test func everySizeDrawsEveryStep() {
        let countdowns = [countdown(), countdown(showsTime: false), countdown(place: tokyo), countdown(icon: .emoji("🧳"))]
        for family in families {
            let size = size(of: family)
            for step in Step.allCases {
                for countdown in countdowns {
                    let image = render(CountingWidget(countdown: countdown, now: step.now, family: family), width: size.width, height: size.height)
                    #expect(ink(image) > 0, "\(family) \(step)")
                }
            }
            #expect(ink(render(EmptyWidget(), width: size.width, height: size.height)) > 0)
        }
        for entry in [CountdownEntry(date: Step.days.now, countdown: countdown()), CountdownEntry(date: Step.days.now, countdown: nil)] {
            #expect(ink(render(CountdownWidgetView(entry: entry), width: 138, height: 138)) > 0)
        }
    }

    @Test func largeAddsTheArrivalOnlyWithAPlace() {
        func height(_ countdown: Countdown, _ step: Step) -> Int {
            render(CountingWidget(countdown: countdown, now: step.now, family: .systemLarge), width: 328)?.height ?? 0
        }
        #expect(height(countdown(place: tokyo), .days) > height(countdown(), .days))
        // From the final day on, there's no weeks, weekends and weekdays row.
        #expect(height(countdown(), .finalDay) < height(countdown(), .days))
        // And once the day has come, no arrival either.
        #expect(height(countdown(place: tokyo), .today) == height(countdown(), .today))
    }

    @Test func everyRunwayDraws() {
        let spans: [(start: Date, moment: Date, now: Date)] = [
            (local(2026, 11, 20), moment, local(2026, 12, 1, 9)), // days
            (start, moment, Step.days.now), // weeks
            (local(2026, 1, 1), local(2030, 1, 20), local(2027, 6, 1)), // months
            (start, moment, Step.finalDay.now), // hours
            (start, moment, Step.after.now), // all the way
        ]
        for style in [WidgetRunway.Style.small, .medium, .large] {
            for span in spans {
                for (isLit, isPast) in [(false, false), (true, false), (false, true)] {
                    let runway = WidgetRunway(style: style, start: span.start, moment: span.moment, now: span.now,
                                              icon: .default, isLit: isLit, isPast: isPast)
                    #expect(ink(render(runway, width: style == .small ? 138 : 328)) > 0)
                }
            }
        }
    }

    @Test func largeRunwayHasRoomForMonthNames() {
        func height(_ style: WidgetRunway.Style) -> Int {
            render(WidgetRunway(style: style, start: start, moment: moment, now: Step.days.now, icon: .default), width: 328)?.height ?? 0
        }
        #expect(height(.large) == Int(RunwayView.height))
        #expect(height(.medium) == 28)
        #expect(height(.small) == 28)
    }
}
