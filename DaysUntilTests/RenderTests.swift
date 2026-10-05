import AppKit
import ServiceManagement
import SwiftUI
import Testing
@testable import DaysUntil

/// A view as SwiftUI draws it, off screen, at 1x.
@MainActor
func render<V: View>(_ view: V, width: CGFloat = 340, height: CGFloat? = nil) -> CGImage? {
    let renderer = ImageRenderer(content: view.frame(width: width, height: height))
    renderer.scale = 1
    return renderer.cgImage
}

/// How many pixels a drawing covers at all.
func ink(_ image: CGImage?) -> Int {
    guard let image else { return 0 }
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return stride(from: 3, to: pixels.count, by: 4).count { pixels[$0] > 0 }
}

/// Wall-clock times on the Mac's own calendar, as the popover reads them.
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
private enum Moment: CaseIterable {
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
}

@Suite @MainActor
struct CountdownViewRenderTests {
    private func height(_ countdown: Countdown, at now: Moment) -> Int {
        render(CountdownView(countdown: countdown, now: now.now, makeMenu: { NSMenu() }, onStartOver: {}))?.height ?? 0
    }

    @Test func everyStepDraws() {
        for now in Moment.allCases {
            for countdown in [countdown(), countdown(showsTime: false), countdown(place: tokyo), countdown(icon: .emoji("🧳"))] {
                let image = render(CountdownView(countdown: countdown, now: now.now, makeMenu: { NSMenu() }, onStartOver: {}))
                #expect(ink(image) > 0, "\(now)")
            }
        }
    }

    @Test func aDateOnlyCountdownAtMidnightHasNoArrivalBox() {
        #expect(height(countdown(showsTime: false), at: .days) < height(countdown(), at: .days))
    }

    @Test func aPlaceAddsItsClock() {
        #expect(height(countdown(place: tokyo), at: .days) > height(countdown(), at: .days))
        // On the day, only the place's clock is left in the box.
        #expect(height(countdown(place: tokyo), at: .today) > height(countdown(), at: .today))
    }

    @Test func theFinalDayLeavesOutTheOtherUnits() {
        #expect(height(countdown(), at: .finalDay) < height(countdown(), at: .finalWeek))
    }

    @Test func theLongDateGivesTheTimeOnlyWhenItHasOne() {
        let dateOnly = countdown(showsTime: false)
        #expect(CountdownView.longDate(of: dateOnly) == dateOnly.targetDate.formatted(date: .complete, time: .omitted))
        let timed = CountdownView.longDate(of: countdown())
        #expect(timed.hasPrefix(moment.formatted(date: .complete, time: .omitted)))
        #expect(timed.contains(moment.formatted(date: .omitted, time: .shortened)))
    }

    @Test func theMoreButtonIsAMenuButtonForVoiceOver() throws {
        let made = Calls<Void>()
        let host = OffscreenHost(MoreButton(makeMenu: { made.record(()); return NSMenu() }), size: CGSize(width: 40, height: 40))
        defer { host.close() }
        let anchor = try #require(host.views(NSView.self).first { String(describing: type(of: $0)).contains("AnchorView") })
        #expect(anchor.isAccessibilityElement())
        #expect(anchor.accessibilityRole() == .menuButton)
        #expect(anchor.accessibilityLabel() == "More")
        // The menu is built only as it opens.
        #expect(made.values.isEmpty)
    }
}

@Suite @MainActor
struct RunwayRenderTests {
    /// The popover's runway is 308 pt wide, a 278 pt track.
    static let width: CGFloat = 308
    static let track: CGFloat = 278

    /// The month names the popover would draw, as positions and widths.
    private func labels(from start: Date, to moment: Date, at now: Date) -> [(x: CGFloat, width: CGFloat)] {
        let found = Calls<(x: CGFloat, width: CGFloat)>()
        let canvas = Canvas { context, _ in
            let runway = CountdownMath.runway(
                start: start, moment: moment, now: now, calendar: .local,
                maxTicks: Int(Self.track / RunwayView.minimumTickSpacing)
            )
            for label in RunwayView.labels(runway, track: Self.track, context: context) {
                found.record((label.x, label.text.measure(in: CGSize(width: 100, height: 20)).width))
            }
        }
        _ = render(canvas, width: Self.track, height: RunwayView.height)
        return found.values
    }

    private func expectApart(_ labels: [(x: CGFloat, width: CGFloat)]) {
        for (label, next) in zip(labels, labels.dropFirst()) {
            #expect(label.x + label.width <= next.x)
        }
        #expect(labels.allSatisfy { $0.x >= 0 && $0.x + $0.width <= Self.track + 0.5 })
    }

    @Test func everyScaleDraws() {
        let spans: [(start: Date, moment: Date, now: Date)] = [
            (local(2026, 11, 20), moment, local(2026, 12, 1, 9)), // days
            (start, moment, local(2026, 10, 4, 10)), // weeks
            (local(2026, 1, 1), local(2030, 1, 20), local(2027, 6, 1)), // months
            (local(2020, 1, 1), local(2040, 1, 1), local(2031, 6, 1)), // years
            (start, moment, local(2026, 12, 17, 19, 57, 53)), // hours
        ]
        for span in spans {
            for (isLit, isPast) in [(false, false), (true, false), (false, true)] {
                let runway = RunwayView(start: span.start, moment: span.moment, now: span.now, icon: .default, isLit: isLit, isPast: isPast)
                #expect(ink(render(runway, width: Self.width)) > 0)
            }
        }
    }

    @Test func monthNamesMarkEachFirstWithoutCrowding() {
        // Aug 3 to Dec 18: the start, then Sep, Oct, Nov and Dec.
        let names = labels(from: start, to: moment, at: local(2026, 10, 4, 10))
        #expect(names.count == 5)
        // The start's name sits at the first week's tick.
        #expect((names.first?.x ?? .infinity) < Self.track / 20)
        expectApart(names)
    }

    @Test func longerSpansThinTheMonths() {
        // Ten months: too tight for every month's name.
        let names = labels(from: local(2026, 1, 1), to: local(2026, 11, 30), at: local(2026, 3, 1))
        #expect(names.count < 11)
        #expect(names.count > 2)
        expectApart(names)
    }

    @Test func spansOfYearsNameTheYears() {
        // From 2026 to 2030, a name each January.
        let names = labels(from: local(2026, 1, 1), to: local(2030, 1, 20), at: local(2027, 6, 1))
        #expect(names.count == 5)
        expectApart(names)
        // Decades: only some years.
        let decades = labels(from: local(2000, 1, 1), to: local(2040, 1, 1), at: local(2026, 6, 1))
        #expect(decades.count < 41)
        #expect(decades.count > 2)
        expectApart(decades)
    }

    @Test func theFinalDayNamesHoursThatFit() {
        let hours = labels(from: start, to: moment, at: local(2026, 12, 17, 19, 57, 53))
        #expect(hours.count >= 3)
        expectApart(hours)
    }
}

@Suite @MainActor
struct OtherViewRenderTests {
    @Test func confettiFallsThenFades() {
        func drawn(startedAgo seconds: TimeInterval) -> Int {
            ink(render(ConfettiView(start: Date().addingTimeInterval(-seconds), originX: 170), width: 340, height: 400))
        }
        #expect(drawn(startedAgo: 0.8) > 0)
        #expect(drawn(startedAgo: ConfettiView.duration + 0.5) == 0)
        // Before it starts, nothing.
        #expect(drawn(startedAgo: -1) == 0)
    }

    @Test func deleteAsksInTheCountdownsPlace() {
        for icon in [CountdownIcon.default, .emoji("🎄")] {
            let view = DeleteConfirmation(countdown: countdown(icon: icon), onCancel: {}, onDelete: {})
            #expect(ink(render(view)) > 0)
        }
    }

    @Test func launchAtLoginSaysWhenItNeedsAttention() {
        let service = LoginServiceStub()
        let login = LaunchAtLogin(service: service)
        func height() -> CGFloat {
            let host = OffscreenHost(LaunchAtLoginFeedback(launchAtLogin: login))
            defer { host.close() }
            return host.fittingSize.height
        }
        #expect(height() == 0)
        service.registeredStatus = .requiresApproval
        login.set(true)
        #expect(height() > 0)
        login.set(false)
        service.registerError = NSError(domain: "test", code: 1)
        login.set(true)
        #expect(login.failedRequest == true)
        #expect(height() > 0)
    }

    @Test func formPiecesDraw() {
        #expect(ink(render(Footnote("Counts down to 17:00 your time."))) > 0)
        #expect(ink(render(Footnote(Text(verbatim: "A note"))))  > 0)
        #expect(ink(render(FieldError(text: Text(verbatim: "Choose a day in the future."))))  > 0)
        for icon in [CountdownIcon.symbol("airplane"), .emoji("🎄")] {
            #expect(ink(render(CountdownIconView(icon: icon).font(.title), width: 40, height: 40)) > 0)
        }
        #expect(ink(render(GroupedBox { Text(verbatim: "Row"); RowDivider(); Text(verbatim: "Row") })) > 0)
        for background in PopoverBackground.allCases {
            for (isActive, isInvalid) in [(false, false), (true, false), (false, true)] {
                let field = Text(verbatim: "Field")
                    .frame(width: 200, height: 24)
                    .fieldBackground(isActive: isActive, isInvalid: isInvalid)
                    .environment(\.popoverBackground, background)
                #expect(ink(render(field, width: 220, height: 40)) > 0)
            }
        }
    }
}

@Suite @MainActor
struct PopoverRenderTests {
    let defaults: UserDefaults = MemoryDefaults()

    private func popover(_ store: CountdownStore, _ state: PopoverState) -> OffscreenHost {
        OffscreenHost(PopoverView(store: store, state: state, makeMenu: { NSMenu() }), size: CGSize(width: 340, height: 800))
    }

    @Test func showsTheFormTheCountdownOrTheQuestion() {
        let store = CountdownStore(defaults: defaults)
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub()))
        let form = popover(store, state)
        let formHeight = form.fittingSize.height
        form.close()

        store.countdown = Countdown(name: "Trip", icon: .default, targetDate: Date().addingTimeInterval(86_400 * 40),
                                    showsTime: true, place: tokyo, startDate: Date().addingTimeInterval(-86_400 * 10))
        state.cancel()
        let shown = popover(store, state)
        let countdownHeight = shown.fittingSize.height
        state.confirmDelete()
        shown.settle()
        let questionHeight = shown.fittingSize.height
        shown.close()

        #expect(formHeight > 0)
        #expect(countdownHeight > 0)
        #expect(questionHeight < countdownHeight)
    }

    @Test func ticksWhileShownAndFollowsTheClock() async throws {
        let store = CountdownStore(defaults: defaults)
        store.popoverBackground = .solid
        store.countdown = Countdown(name: "Trip", icon: .default, targetDate: Date().addingTimeInterval(30),
                                    showsTime: true, place: nil, startDate: Date().addingTimeInterval(-86_400))
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub()))
        let host = popover(store, state)
        defer {
            state.isShown = false
            host.close()
        }
        state.isShown = true
        // Its tasks and notifications run on the main actor once the test lets go of it.
        try await Task.sleep(for: .milliseconds(1_100))
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            NotificationCenter.default.post(name: name, object: nil)
        }
        try await Task.sleep(for: .milliseconds(100))
        state.edit()
        try await Task.sleep(for: .milliseconds(1_100))
        #expect(state.isEditing)
        #expect(state.draft.name == "Trip")
        #expect(state.draft.timeZone == .current)
        #expect(host.fittingSize.height > 0)
    }

    @Test func celebratesTheDayOnceAnOpening() async throws {
        let store = CountdownStore(defaults: defaults)
        store.countdown = Countdown(name: "Trip", icon: .default, targetDate: Date().addingTimeInterval(-1),
                                    showsTime: true, place: nil, startDate: Date().addingTimeInterval(-86_400))
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub()))
        let host = popover(store, state)
        defer {
            state.isShown = false
            host.close()
        }
        state.isShown = true
        try await Task.sleep(for: .milliseconds(300))
        let image = render(PopoverView(store: store, state: state, makeMenu: { NSMenu() }))
        #expect(ink(image) > 0)
        state.isShown = false
        try await Task.sleep(for: .milliseconds(100))
        #expect(state.openedAt != nil)
    }
}
