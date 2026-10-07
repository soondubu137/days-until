import AppKit
import Combine
import Testing
@testable import DaysUntil

@MainActor
final class UpdaterServiceStub: UpdaterService {
    var automaticallyChecksForUpdates = true
    var automaticallyDownloadsUpdates = true
    var lastUpdateCheckDate: Date?
    var canCheckForUpdates = true
    var checks = 0
    func checkForUpdates() { checks += 1 }
}

/// Sparkle's side faked, with a clock that moves only when told to and a display that sleeps on cue.
@MainActor
final class UpdatesFixture {
    let service = UpdaterServiceStub()
    let defaults: UserDefaults = MemoryDefaults()
    var now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    var displaysAreAsleep = false
    let displaysDidSleep = PassthroughSubject<Void, Never>()
    let opened = Calls<URL>()
    let installs = Calls<Void>()
    let sparkleShown = Calls<Void>()
    let sparkleFinished = Calls<Void>()

    func make(version: String? = "0.3.0", lastLaunched: String? = nil) -> Updates {
        if let lastLaunched { defaults.set(lastLaunched, forKey: "lastLaunchedVersion") }
        let updates = Updates(
            service: service, defaults: defaults, version: version,
            now: { [unowned self] in now },
            displaysAreAsleep: { [unowned self] in displaysAreAsleep },
            displaysDidSleep: displaysDidSleep.eraseToAnyPublisher(),
            openURL: { [unowned self] in opened.record($0) }
        )
        updates.willShowSparkle = { [unowned self] in sparkleShown.record(()) }
        updates.didFinishSparkle = { [unowned self] in sparkleFinished.record(()) }
        return updates
    }

    func waitToInstall(_ updates: Updates, version: String = "0.3.1") {
        updates.sparkleWillInstallOnQuit(version: version) { [unowned self] in installs.record(()) }
    }

    func pass(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
}

@Suite @MainActor
struct UpdatesTests {
    let fixture = UpdatesFixture()
    let day: TimeInterval = 24 * 60 * 60

    @Test func thePolicyIsSparklesTwoSettings() {
        let updates = fixture.make()
        #expect(updates.policy == .installAutomatically)
        updates.policy = .askFirst
        #expect(fixture.service.automaticallyChecksForUpdates)
        #expect(!fixture.service.automaticallyDownloadsUpdates)
        updates.policy = .off
        #expect(!fixture.service.automaticallyChecksForUpdates)
        #expect(updates.policy == .off)
        updates.policy = .installAutomatically
        #expect(fixture.service.automaticallyChecksForUpdates)
        #expect(fixture.service.automaticallyDownloadsUpdates)
    }

    @Test func aFoundUpdateWaitsInThePopoverUntilAnswered() {
        let updates = fixture.make()
        updates.policy = .askFirst
        #expect(updates.line == nil)
        updates.sparkleFound(version: "0.3.1")
        #expect(updates.line == .available("0.3.1"))
        updates.details()
        #expect(fixture.sparkleShown.values.count == 1)
        #expect(fixture.service.checks == 1)
        // Brought to the front in Sparkle's window, or answered there.
        updates.sparkleGotAttention()
        #expect(updates.line == nil)
    }

    @Test func laterHidesTheLineUntilTheNextDailyCheck() {
        let updates = fixture.make()
        updates.policy = .askFirst
        updates.sparkleFound(version: "0.3.1")
        updates.later()
        #expect(updates.line == nil)
        fixture.pass(day - 60)
        updates.popoverOpened()
        #expect(updates.line == nil)
        updates.popoverClosed()
        fixture.pass(60)
        updates.popoverOpened()
        #expect(updates.line == .available("0.3.1"))
    }

    @Test func dontCheckHidesAFoundUpdate() {
        let updates = fixture.make()
        updates.policy = .askFirst
        updates.sparkleFound(version: "0.3.1")
        updates.policy = .off
        #expect(updates.line == nil)
    }

    @Test func theEndOfSparklesSessionClearsTheLineAndHandsBack() {
        let updates = fixture.make()
        updates.policy = .askFirst
        updates.sparkleFound(version: "0.3.1")
        updates.sparkleSessionEnded()
        #expect(updates.line == nil)
        #expect(fixture.sparkleFinished.values.count == 1)
    }

    @Test func aDownloadedUpdateInstallsWhileTheDisplaySleeps() {
        let updates = fixture.make()
        var canRelaunch = true
        updates.canRelaunch = { canRelaunch }
        fixture.waitToInstall(updates)
        #expect(fixture.installs.values.isEmpty)
        #expect(updates.line == nil)

        // Never while the popover is open, or while the form holds an edit.
        updates.popoverOpened()
        fixture.displaysDidSleep.send()
        #expect(fixture.installs.values.isEmpty)
        updates.popoverClosed()
        canRelaunch = false
        fixture.displaysDidSleep.send()
        #expect(fixture.installs.values.isEmpty)

        canRelaunch = true
        fixture.displaysDidSleep.send()
        #expect(fixture.installs.values.count == 1)
    }

    @Test func onlyInstallAutomaticallyInstallsOutOfSight() {
        let updates = fixture.make()
        fixture.waitToInstall(updates)
        #expect(updates.line == nil)
        // Chosen after the download: it's no longer the app's to install, so the line asks at once.
        for policy in [UpdatePolicy.askFirst, .off] {
            updates.policy = policy
            #expect(updates.line == .ready("0.3.1"))
            fixture.displaysDidSleep.send()
            #expect(fixture.installs.values.isEmpty)
        }
        updates.policy = .installAutomatically
        #expect(updates.line == nil)
        fixture.displaysDidSleep.send()
        #expect(fixture.installs.values.count == 1)
    }

    @Test func anUpdateReadyWhileTheDisplaySleepsInstallsAtOnce() {
        fixture.displaysAreAsleep = true
        let updates = fixture.make()
        fixture.waitToInstall(updates)
        #expect(fixture.installs.values.count == 1)
    }

    @Test func aWeekWithoutTheDisplaySleepingOffersItInThePopover() {
        let updates = fixture.make()
        fixture.waitToInstall(updates)
        fixture.pass(6 * day)
        updates.popoverOpened()
        #expect(updates.line == nil)
        updates.popoverClosed()
        fixture.pass(day)
        updates.popoverOpened()
        #expect(updates.line == .ready("0.3.1"))
        updates.later()
        #expect(updates.line == nil)
        updates.popoverClosed()
        fixture.pass(day)
        updates.popoverOpened()
        #expect(updates.line == .ready("0.3.1"))
        updates.installAndRelaunch()
        #expect(fixture.installs.values.count == 1)
    }

    @Test func checkingWithAnUpdateWaitingOffersItAtOnce() {
        let updates = fixture.make()
        updates.checkForUpdates()
        #expect(fixture.service.checks == 1)
        #expect(fixture.sparkleShown.values.count == 1)

        // Sparkle's session stays open while the app holds the install, so it can't check itself.
        fixture.service.canCheckForUpdates = false
        #expect(!updates.canCheckForUpdates)
        fixture.waitToInstall(updates)
        #expect(updates.canCheckForUpdates)
        updates.popoverOpened()
        updates.later()
        updates.checkForUpdates()
        #expect(updates.line == .ready("0.3.1"))
        #expect(fixture.service.checks == 1)
        #expect(fixture.sparkleShown.values.count == 1)
    }

    @Test func theFirstOpeningAfterAnUpdateSaysSoOnce() throws {
        let updates = fixture.make(version: "0.3.0", lastLaunched: "0.2.1")
        #expect(fixture.defaults.string(forKey: "lastLaunchedVersion") == "0.3.0")
        updates.popoverOpened()
        #expect(updates.line == .updated("0.3.0"))
        updates.whatsNew()
        #expect(fixture.opened.values == [URL(string: "https://github.com/soondubu137/days-until/releases/tag/v0.3.0")!])
        updates.popoverClosed()
        #expect(updates.line == nil)
        updates.popoverOpened()
        #expect(updates.line == nil)
    }

    @Test func onlyANewerVersionCountsAsAnUpdate() {
        #expect(fixture.make(version: "0.3.0").line == nil)
        #expect(fixture.make(version: "0.3.0", lastLaunched: "0.3.0").line == nil)
        #expect(fixture.make(version: "0.9.0", lastLaunched: "0.10.0").line == nil)
        #expect(fixture.make(version: "0.10.0", lastLaunched: "0.9.0").line == .updated("0.10.0"))
    }

    @Test func aDecisionOutranksTheUpdatedLine() {
        let updates = fixture.make(version: "0.3.0", lastLaunched: "0.2.1")
        updates.policy = .askFirst
        updates.sparkleFound(version: "0.3.1")
        #expect(updates.line == .available("0.3.1"))
        updates.later()
        #expect(updates.line == .updated("0.3.0"))
    }
}

@Suite @MainActor
struct UpdatesInThePopoverTests {
    let fixture = UpdatesFixture()

    private func state(_ store: CountdownStore, _ updates: Updates?) -> PopoverState {
        PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub()), updates: updates)
    }

    @Test func openingAndClosingThePopoverReachUpdates() {
        let updates = fixture.make(version: "0.3.0", lastLaunched: "0.2.1")
        let state = state(CountdownStore(defaults: fixture.defaults), updates)
        state.isShown = true
        #expect(updates.line == .updated("0.3.0"))
        state.isShown = false
        #expect(updates.line == nil)
    }

    @Test func theFormHoldsAnEditWhileItHasSomethingToLose() {
        let store = CountdownStore(defaults: fixture.defaults)
        let state = state(store, nil)
        #expect(state.isEditing)
        #expect(!state.holdsAnEdit)
        state.draft.name = "Trip"
        #expect(state.holdsAnEdit)
        store.countdown = Countdown(name: "Trip", icon: .default, targetDate: Date().addingTimeInterval(86_400 * 30),
                                    showsTime: false, place: nil, startDate: Date())
        state.cancel()
        #expect(!state.holdsAnEdit)
        state.edit()
        #expect(state.holdsAnEdit)
    }

    @Test func eachLineDrawsAndNoneTakesNoRoom() {
        let updates = fixture.make()
        func height() -> CGFloat {
            let host = OffscreenHost(UpdateFeedback(updates: updates))
            defer { host.close() }
            return host.fittingSize.height
        }
        #expect(height() == 0)
        updates.policy = .askFirst
        updates.sparkleFound(version: "0.3.1")
        #expect(height() > 0)
        updates.sparkleGotAttention()
        fixture.waitToInstall(updates)
        updates.checkForUpdates()
        #expect(updates.line == .ready("0.3.1"))
        #expect(height() > 0)
        let updated = fixture.make(version: "0.3.0", lastLaunched: "0.2.1")
        #expect(updated.line == .updated("0.3.0"))
        let host = OffscreenHost(UpdateFeedback(updates: updated))
        #expect(host.fittingSize.height > 0)
        host.close()
    }
}

@Suite @MainActor
struct UpdatesInTheMenuTests {
    let fixture = UpdatesFixture()

    private func menu(_ updates: Updates?) -> (MoreMenu, NSMenu) {
        let store = CountdownStore(defaults: fixture.defaults)
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub()), updates: updates)
        let more = MoreMenu(store: store, state: state)
        return (more, more.make())
    }

    private func choose(_ item: NSMenuItem?) throws {
        let item = try #require(item)
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
    }

    @Test func updatesOffersThePolicies() throws {
        let updates = fixture.make()
        let (more, menu) = menu(updates)
        defer { withExtendedLifetime(more) {} }
        let submenu = try #require(menu.item(withTitle: "Updates")?.submenu)
        #expect(submenu.items.map(\.title) == ["Install Automatically", "Ask Before Installing", "Don't Check"])
        #expect(submenu.items.map(\.state) == [.on, .off, .off])
        try choose(submenu.items[1])
        #expect(updates.policy == .askFirst)
        try choose(submenu.items[2])
        #expect(updates.policy == .off)
        try choose(submenu.items[0])
        #expect(updates.policy == .installAutomatically)
        let again = try #require(more.make().item(withTitle: "Updates")?.submenu)
        #expect(again.items.first?.state == .on)
    }

    @Test func updatesSaysWhenSparkleLastLooked() throws {
        let updates = fixture.make()
        fixture.service.lastUpdateCheckDate = Date()
        let (more, menu) = menu(updates)
        defer { withExtendedLifetime(more) {} }
        let submenu = try #require(menu.item(withTitle: "Updates")?.submenu)
        let last = try #require(submenu.items.last)
        #expect(last.title.hasPrefix("Last checked: "))
        #expect(!last.isEnabled)
        #expect(submenu.items[submenu.items.count - 2].isSeparatorItem)
    }

    @Test func checkForUpdatesSitsUnderAbout() throws {
        let updates = fixture.make()
        let (more, menu) = menu(updates)
        defer { withExtendedLifetime(more) {} }
        let titles = menu.items.map(\.title)
        let about = try #require(titles.firstIndex(of: "About Days Until"))
        #expect(titles[about + 1] == "Check for Updates…")
        let check = menu.items[about + 1]
        #expect(check.isEnabled)
        try choose(check)
        #expect(fixture.service.checks == 1)

        fixture.service.canCheckForUpdates = false
        #expect(more.make().item(withTitle: "Check for Updates…")?.isEnabled == false)
    }

    @Test func noUpdateItemsWithoutSparkle() {
        let (more, menu) = menu(nil)
        defer { withExtendedLifetime(more) {} }
        #expect(menu.item(withTitle: "Updates") == nil)
        #expect(menu.item(withTitle: "Check for Updates…") == nil)
    }
}
