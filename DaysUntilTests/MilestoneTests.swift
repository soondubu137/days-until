import AppKit
import Testing
@testable import DaysUntil

private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
private let tokyo = Place(timeZoneID: "Asia/Tokyo", name: "Tokyo")

private func calendar(_ zone: TimeZone) -> Calendar {
    CountdownMath.gregorian(in: zone)
}

private func date(_ zone: TimeZone, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar(zone).date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// When each milestone arrives and what it says, worked out from the countdown alone.
struct MilestoneScheduleTests {
    let la = calendar(losAngeles)

    private func countdown(_ moment: Date, showsTime: Bool = true, place: Place? = nil) -> Countdown {
        Countdown(name: "Going home", icon: .default, targetDate: moment, showsTime: showsTime, place: place,
                  startDate: date(losAngeles, 2026, 8, 3))
    }

    private func long(_ moment: Date, year: Bool = false) -> String {
        let style = Date.FormatStyle(calendar: la, timeZone: losAngeles).weekday(.wide).month(.wide).day()
        return moment.formatted(year ? style.year() : style)
    }

    private func time(_ moment: Date, in zone: TimeZone, weekday: Bool = false) -> String {
        let style = Date.FormatStyle(calendar: calendar(zone), timeZone: zone).hour().minute()
        return moment.formatted(weekday ? style.weekday(.abbreviated) : style)
    }

    @Test func theDaysBeforeArriveAt9AMAndTheDayAtTheMoment() {
        let moment = date(losAngeles, 2026, 12, 18, 9, 40)
        let milestones = CountdownMath.milestones(of: countdown(moment, place: tokyo), now: date(losAngeles, 2026, 8, 3), calendar: la)
        #expect(milestones.map(\.days) == [100, 30, 7, 1, 0])
        #expect(milestones.map(\.date) == [
            date(losAngeles, 2026, 9, 9, 9), date(losAngeles, 2026, 11, 18, 9), date(losAngeles, 2026, 12, 11, 9),
            date(losAngeles, 2026, 12, 17, 9), moment,
        ])
        let day = long(moment)
        #expect(milestones[0].body == String(localized: "\(100) days to go · \(day)"))
        #expect(milestones[0].body.hasPrefix("100 days to go · "))
        #expect(milestones[1].body == String(localized: "\(30) days to go · \(day)"))
        #expect(milestones[2].body == String(localized: "A week to go · \(day)"))
        // 2:40 AM the next day in Tokyo, so with its weekday.
        #expect(milestones[3].body == String(localized: "Tomorrow at \(time(moment, in: losAngeles)) · \(time(moment, in: tokyo.timeZone!, weekday: true)) in \("Tokyo")"))
        #expect(milestones[4].body == "Today’s the day.")
    }

    @Test func theCountAgreesWithEachOne() {
        // Across daylight saving in both directions, and in zones with half-hour shifts.
        for identifier in ["America/Los_Angeles", "Europe/London", "Australia/Lord_Howe", "America/Santiago", "Asia/Kolkata"] {
            let zone = TimeZone(identifier: identifier)!
            for (month, hour) in [(3, 0), (4, 6), (10, 23), (11, 9)] {
                let moment = date(zone, 2027, month, 8, hour, 30)
                for milestone in CountdownMath.milestones(of: countdown(moment), now: date(zone, 2026, 1, 1), calendar: calendar(zone)) where milestone.days > 0 {
                    #expect(CountdownMath.daysLeft(from: milestone.date, to: moment, calendar: calendar(zone)) == milestone.days, "\(identifier) \(month)")
                    #expect(CountdownMath.timeOfDay(of: milestone.date, in: zone) == CountdownMath.milestoneTime)
                }
            }
        }
    }

    @Test func aDateOnlyCountdownHasItsDayAt9AMAndNoTime() {
        let moment = date(losAngeles, 2026, 12, 18)
        let milestones = CountdownMath.milestones(of: countdown(moment, showsTime: false, place: tokyo), now: date(losAngeles, 2026, 12, 1), calendar: la)
        #expect(milestones.map(\.days) == [7, 1, 0])
        #expect(milestones[1].body == String(localized: "Tomorrow · \(long(moment))"))
        #expect(milestones[2].date == date(losAngeles, 2026, 12, 18, 9))

        // After travel the same instant is 3 AM in New York: still a date-only countdown, but no
        // longer at midnight, so the day before gives its time.
        let newYork = TimeZone(identifier: "America/New_York")!
        let there = CountdownMath.milestones(of: countdown(moment, showsTime: false), now: date(losAngeles, 2026, 12, 1), calendar: calendar(newYork))
        #expect(there[1].body == String(localized: "Tomorrow at \(time(moment, in: newYork))"))
        // And the day waits for 9:00 AM there.
        #expect(there[2].date == date(newYork, 2026, 12, 18, 9))
    }

    @Test func onlyWhatsAhead() {
        let moment = date(losAngeles, 2026, 12, 18, 9, 40)
        let after = CountdownMath.milestones(of: countdown(moment), now: date(losAngeles, 2026, 11, 18, 10), calendar: la)
        #expect(after.map(\.days) == [7, 1, 0])
        let before = CountdownMath.milestones(of: countdown(moment), now: date(losAngeles, 2026, 11, 18, 8, 59), calendar: la)
        #expect(before.map(\.days) == [30, 7, 1, 0])
        #expect(CountdownMath.milestones(of: countdown(moment), now: moment, calendar: la).isEmpty)
    }

    @Test func anotherYearSaysSo() {
        let moment = date(losAngeles, 2027, 1, 9)
        let milestones = CountdownMath.milestones(of: countdown(moment, showsTime: false), now: date(losAngeles, 2026, 9, 1), calendar: la)
        #expect(milestones[0].body == String(localized: "\(100) days to go · \(long(moment, year: true))"))
        // A week before is already in 2027.
        #expect(milestones[2].body == String(localized: "A week to go · \(long(moment))"))
    }
}

/// macOS's notifications, as a stand-in that never asks the person anything.
@MainActor
final class NotificationServiceStub: NotificationService {
    /// macOS's permission so far: nil until it has asked.
    var allowed: Bool?
    /// What the person answers at macOS's prompt.
    var answer = true
    var requests = 0
    var settingsCalls = 0
    var pending: [String: MilestoneNotice] = [:]
    var deliveredMilestones: [DeliveredMilestone] = []
    var removedDelivered: [String] = []

    func isAllowed() async -> Bool? { allowed }

    func requestPermission() async -> Bool {
        requests += 1
        allowed = answer
        return answer
    }

    func add(_ notices: [MilestoneNotice]) async {
        for notice in notices { pending[notice.identifier] = notice }
    }

    func removePending(_ identifiers: [String]) {
        for identifier in identifiers { pending[identifier] = nil }
    }

    func delivered() async -> [DeliveredMilestone] { deliveredMilestones }

    func removeDelivered(_ identifiers: [String]) { removedDelivered += identifiers }

    func openSettings() { settingsCalls += 1 }
}

@Suite @MainActor
struct MilestoneNotificationsTests {
    let defaults: UserDefaults = MemoryDefaults()
    let service = NotificationServiceStub()

    /// 120 days out, so all five are ahead.
    private func countdown(days: Double = 120) -> Countdown {
        Countdown(name: "Going home", icon: .default, targetDate: Date().addingTimeInterval(days * 86_400),
                  showsTime: true, place: nil, startDate: Date())
    }

    private func milestones(_ countdown: Countdown? = nil) async -> (CountdownStore, MilestoneNotifications) {
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown ?? self.countdown()
        let milestones = MilestoneNotifications(store: store, service: service)
        await milestones.settle()
        return (store, milestones)
    }

    @Test func offUntilSomeoneSaysYes() async {
        let (store, milestones) = await milestones()
        #expect(!store.notifiesAtMilestones)
        #expect(milestones.state == .off)
        #expect(service.requests == 0)
        #expect(service.pending.isEmpty)
    }

    @Test func turningItOnAsksOnceThenSchedulesWhatsAhead() async {
        let (store, milestones) = await milestones()
        milestones.set(true)
        await milestones.settle()
        #expect(service.requests == 1)
        #expect(store.notifiesAtMilestones)
        #expect(milestones.state == .on)
        #expect(service.pending.keys.sorted() == ["milestone.0", "milestone.1", "milestone.100", "milestone.30", "milestone.7"])
        #expect(service.pending.values.allSatisfy { $0.title == "Going home" })

        milestones.toggle()
        await milestones.settle()
        #expect(!store.notifiesAtMilestones)
        #expect(service.pending.isEmpty)
        milestones.toggle()
        await milestones.settle()
        // macOS asks only once.
        #expect(service.requests == 1)
        #expect(service.pending.count == 5)
    }

    @Test func dontAllowTurnsItBackOff() async {
        service.answer = false
        let (store, milestones) = await milestones()
        milestones.set(true)
        await milestones.settle()
        #expect(service.requests == 1)
        #expect(!store.notifiesAtMilestones)
        #expect(milestones.state == .off)
        #expect(service.pending.isEmpty)
    }

    @Test func afterADontAllowItOpensSystemSettingsAndShowsADash() async {
        service.allowed = false
        let (store, milestones) = await milestones()
        milestones.set(true)
        await milestones.settle()
        #expect(service.requests == 0)
        #expect(service.settingsCalls == 1)
        #expect(store.notifiesAtMilestones)
        #expect(milestones.state == .mixed)
        #expect(service.pending.isEmpty)

        // Allowed in System Settings, then the popover opens.
        service.allowed = true
        milestones.refresh()
        await milestones.settle()
        #expect(milestones.state == .on)
        #expect(service.pending.count == 5)
    }

    @Test func theScheduleFollowsTheCountdown() async {
        service.allowed = true
        let (store, milestones) = await milestones()
        milestones.set(true)
        await milestones.settle()
        #expect(service.pending.count == 5)

        let countdown = store.countdown
        store.countdown = nil
        await milestones.settle()
        #expect(service.pending.isEmpty)
        // Undo.
        store.countdown = countdown
        await milestones.settle()
        #expect(service.pending.count == 5)

        store.countdown = self.countdown(days: 50)
        await milestones.settle()
        #expect(service.pending.keys.sorted() == ["milestone.0", "milestone.1", "milestone.30", "milestone.7"])
        #expect(service.pending["milestone.30"]?.body.hasPrefix("30 days to go · ") == true)
    }

    @Test func theAppNeverAsksOnItsOwn() async {
        // On, but macOS hasn't asked: nothing is scheduled until a yes in the app asks it.
        defaults.set(true, forKey: "notifiesAtMilestones")
        let (store, milestones) = await milestones()
        #expect(store.notifiesAtMilestones)
        milestones.refresh()
        await milestones.settle()
        #expect(service.requests == 0)
        #expect(service.pending.isEmpty)
    }

    @Test func aMilestoneDeliveredOnALaterDayIsTakenBack() async {
        let now = Date()
        service.deliveredMilestones = [
            DeliveredMilestone(identifier: "milestone.30", delivered: now, due: now.addingTimeInterval(-2 * 86_400)),
            DeliveredMilestone(identifier: "milestone.7", delivered: now, due: now),
        ]
        _ = await milestones()
        #expect(service.removedDelivered == ["milestone.30"])
    }

    @Test func persistsAcrossLaunches() async {
        service.allowed = true
        let (_, milestones) = await milestones()
        milestones.set(true)
        await milestones.settle()
        #expect(CountdownStore(defaults: defaults).notifiesAtMilestones)
    }
}

@Suite @MainActor
struct NotifyMeMenuTests {
    let defaults: UserDefaults = MemoryDefaults()
    let service = NotificationServiceStub()
    let countdown = Countdown(name: "Trip", icon: .symbol("airplane"), targetDate: Date().addingTimeInterval(86_400 * 120),
                              showsTime: false, place: nil, startDate: Date())

    private func choose(_ item: NSMenuItem?) throws {
        let item = try #require(item)
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
    }

    private func state(_ store: CountdownStore) async -> PopoverState {
        let milestones = MilestoneNotifications(store: store, service: service)
        await milestones.settle()
        return PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub()), milestones: milestones)
    }

    @Test func notifyMeSitsUnderLaunchAtLoginAndNamesTheMilestonesInItsTooltip() async throws {
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        let state = await state(store)
        let more = MoreMenu(store: store, state: state)
        defer { withExtendedLifetime(more) {} }
        let menu = more.make()
        let notify = try #require(menu.item(withTitle: "Notify Me"))
        #expect(menu.index(of: notify) == menu.indexOfItem(withTitle: "Launch at Login") + 1)
        #expect(notify.toolTip == "At 100, 30 and 7 days, the day before, and on the day")
        #expect(notify.state == .off)
        #expect(menu.item(withTitle: "Notification Settings…") == nil)

        try choose(notify)
        await state.milestones?.settle()
        #expect(store.notifiesAtMilestones)
        #expect(service.requests == 1)
        #expect(more.make().item(withTitle: "Notify Me")?.state == .on)
    }

    @Test func whileMacOSHasThemOffItShowsADashAndTheSettings() async throws {
        service.allowed = false
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        store.notifiesAtMilestones = true
        let state = await state(store)
        let more = MoreMenu(store: store, state: state)
        defer { withExtendedLifetime(more) {} }
        let menu = more.make()
        let notify = try #require(menu.item(withTitle: "Notify Me"))
        #expect(notify.state == .mixed)
        let settings = try #require(menu.item(withTitle: "Notification Settings…"))
        #expect(menu.index(of: settings) == menu.index(of: notify) + 1)
        try choose(settings)
        #expect(service.settingsCalls == 1)
        // A click on the dash turns it off.
        try choose(notify)
        await state.milestones?.settle()
        #expect(!store.notifiesAtMilestones)
        #expect(more.make().item(withTitle: "Notification Settings…") == nil)
    }

    @Test func aNewInstallLeavesItToTheForm() async {
        let store = CountdownStore(defaults: defaults)
        let state = await state(store)
        #expect(MoreMenu(store: store, state: state).make().item(withTitle: "Notify Me") == nil)
        store.countdown = countdown
        store.countdown = nil
        // Deleted: the form no longer offers it, so the menu does.
        #expect(MoreMenu(store: store, state: state).make().item(withTitle: "Notify Me") != nil)
    }

    @Test func theFormsCheckboxIsAYes() async throws {
        let store = CountdownStore(defaults: defaults)
        let state = await state(store)
        state.draft.name = "Trip"
        #expect(state.draft.notifiesAtMilestones)
        state.save(try #require(state.draft.validatedCountdown(now: Date())))
        await state.milestones?.settle()
        #expect(service.requests == 1)
        #expect(store.notifiesAtMilestones)
        #expect(!service.pending.isEmpty)
    }

    @Test func anUntickedCheckboxAsksNothing() async throws {
        let store = CountdownStore(defaults: defaults)
        let state = await state(store)
        state.draft.name = "Trip"
        state.draft.notifiesAtMilestones = false
        state.save(try #require(state.draft.validatedCountdown(now: Date())))
        await state.milestones?.settle()
        #expect(service.requests == 0)
        #expect(!store.notifiesAtMilestones)

        // Later saves, from the edit form, leave the switch to the menu.
        state.edit()
        state.save(try #require(state.draft.validatedCountdown(now: Date())))
        await state.milestones?.settle()
        #expect(service.requests == 0)
    }
}
