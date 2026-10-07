import AppKit
import ServiceManagement
import Testing
@testable import DaysUntil

@Suite @MainActor
struct MenuBarLabelTests {
    private func button(_ icon: CountdownIcon?, _ text: CountdownMath.MenuBarText?) -> NSStatusBarButton {
        let button = NSStatusBarButton(frame: .zero)
        MenuBarLabel(icon: icon, text: text).apply(to: button)
        return button
    }

    /// The icon as it'll be drawn, which also runs its drawing.
    private func drawn(_ button: NSStatusBarButton) -> CGImage? {
        var rect = CGRect(origin: .zero, size: button.image?.size ?? .zero)
        return button.image?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    @Test func withNothingSetItAsksForADate() {
        let button = button(nil, nil)
        #expect(button.attributedTitle.string == "Set date")
        #expect(button.imagePosition == .imageLeading)
        #expect(button.image?.isTemplate == true)
        #expect(button.accessibilityLabel() == "Days Until: Set date")
        #expect(ink(drawn(button)) > 0)
    }

    @Test func unitsSitCloserThanWords() throws {
        let title = button(.default, .remaining("6d 14h")).attributedTitle
        #expect(title.string == "6d 14h")
        let kern = try #require(title.attribute(.kern, at: 2, effectiveRange: nil) as? CGFloat)
        #expect(kern < 0)
        // Natural digits outside a clock.
        let font = try #require(title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.fontDescriptor.object(forKey: .featureSettings) == nil)
    }

    @Test func aTickingClockHasFixedWidthDigits() throws {
        let title = button(.default, .remaining("13:42:07")).attributedTitle
        let font = try #require(title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.fontDescriptor.object(forKey: .featureSettings) != nil)
    }

    @Test func onTheDayTheIconTakesTheAccent() {
        let button = button(.default, .today)
        #expect(button.attributedTitle.string == "Today")
        // Tinted, so not a template the menu bar would recolour.
        #expect(button.image?.isTemplate == false)
        #expect(ink(drawn(button)) > 0)
    }

    @Test func iconOnlyHasNoTitle() throws {
        let button = button(.default, .iconOnly)
        #expect(button.attributedTitle.length == 0)
        #expect(button.imagePosition == .imageOnly)
        #expect(button.accessibilityLabel() == "Days Until")
        // Centred, 2 pt beyond the icon's ink on either side, on whole points.
        let image = try #require(button.image)
        #expect(image.size.height == 22)
        #expect(image.size.width == image.size.width.rounded())
    }

    @Test func anEmojiKeepsItsColours() {
        let button = button(.emoji("🎄"), .remaining("81d"))
        #expect(button.image?.isTemplate == false)
        #expect(ink(drawn(button)) > 0)
        // Drawn the same way a second time, from the measured ink.
        #expect(self.button(.emoji("🎄"), .remaining("80d")).image?.size.width == button.image?.size.width)
    }

    @Test func anUnknownSymbolStillLeavesRoom() {
        let button = button(.symbol("no.such.symbol.here"), .remaining("3d"))
        #expect((button.image?.size.width ?? 0) > 0)
    }
}

@Suite @MainActor
struct MenuBarClockTests {
    let defaults: UserDefaults = MemoryDefaults()

    private func countdown(in seconds: TimeInterval) -> Countdown {
        Countdown(name: "Trip", icon: .default, targetDate: Date().addingTimeInterval(seconds), showsTime: true,
                  place: nil, startDate: Date().addingTimeInterval(-86_400))
    }

    private func expected(_ countdown: Countdown, _ style: MenuBarStyle) -> CountdownMath.MenuBarText {
        CountdownMath.menuBarDisplay(moment: countdown.targetDate, style: style, now: Date(), calendar: .local).text
    }

    @Test func followsTheCountdownAndTheStyle() {
        let store = CountdownStore(defaults: defaults)
        let clock = MenuBarClock(store: store)
        #expect(clock.text == nil)
        let countdown = countdown(in: 86_400 * 40)
        store.countdown = countdown
        #expect(clock.text == expected(countdown, .adaptive))
        store.menuBarStyle = .daysAndHours
        #expect(clock.text == expected(countdown, .daysAndHours))
        store.menuBarStyle = .iconOnly
        #expect(clock.text == .iconOnly)
        store.countdown = nil
        #expect(clock.text == nil)
    }

    @Test func ticksAtTheNextChange() throws {
        let store = CountdownStore(defaults: defaults)
        store.menuBarStyle = .alwaysSeconds
        store.countdown = countdown(in: 30)
        let clock = MenuBarClock(store: store)
        let first = clock.text
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        #expect(clock.text != first)
    }

    @Test func recomputesWhenTheClockOrTimeZoneChanges() async throws {
        let store = CountdownStore(defaults: defaults)
        store.menuBarStyle = .alwaysSeconds
        let countdown = countdown(in: 86_400 * 3)
        store.countdown = countdown
        let clock = MenuBarClock(store: store)
        let before = clock.text
        // Recomputed, it reads what the clock says then.
        try await Task.sleep(for: .milliseconds(1_100))
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange, .NSCalendarDayChanged] {
            NotificationCenter.default.post(name: name, object: nil)
        }
        try await Task.sleep(for: .milliseconds(50))
        #expect(clock.text != before)
        #expect(clock.text == expected(countdown, .alwaysSeconds))
    }
}

@Suite @MainActor
struct MenuBarPanelTests {
    @Test func escapeAsksToClose() {
        let panel = MenuBarPanel(content: NSView())
        let cancelled = Calls<Void>()
        panel.onCancel = { cancelled.record(()) }
        panel.cancelOperation(nil)
        #expect(cancelled.values.count == 1)
        #expect(panel.canBecomeKey)
        #expect(panel.level.rawValue == NSWindow.Level.mainMenu.rawValue - 1)
    }
}

@Suite @MainActor
struct MoreMenuTests {
    let defaults: UserDefaults = MemoryDefaults()
    let service = LoginServiceStub()
    let countdown = Countdown(name: "Trip", icon: .symbol("airplane"), targetDate: Date().addingTimeInterval(86_400 * 30),
                              showsTime: false, place: nil, startDate: Date())

    /// The menu, and what it acts on. Its items hold their target weakly, so keep `more` while
    /// choosing them.
    private func menu() -> (CountdownStore, PopoverState, MoreMenu, NSMenu) {
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: service))
        let more = MoreMenu(store: store, state: state)
        return (store, state, more, more.make())
    }

    private func choose(_ item: NSMenuItem?) throws {
        let item = try #require(item)
        #expect(NSApp.sendAction(try #require(item.action), to: item.target, from: item))
    }

    @Test func editOpensTheForm() throws {
        let (_, state, more, menu) = menu()
        try choose(menu.item(withTitle: "Edit Countdown…"))
        #expect(state.isEditing)
        #expect(state.draft.name == "Trip")
        withExtendedLifetime(more) {}
    }

    @Test func eachStyleShowsWhatItWouldReadAndPicksIt() throws {
        let (store, _, more, menu) = menu()
        defer { withExtendedLifetime(more) {} }
        let styles = try #require(menu.item(withTitle: "Menu Bar")?.submenu)
        #expect(styles.items.count == MenuBarStyle.allCases.count)
        #expect(styles.items.first?.state == .on)
        // A preview after a tab, except for Icon only.
        #expect(styles.items.dropLast().allSatisfy { $0.attributedTitle?.string.contains("\t") == true })
        for (item, style) in zip(styles.items, MenuBarStyle.allCases) {
            try choose(item)
            #expect(store.menuBarStyle == style)
        }
    }

    @Test func backgroundIsAChoiceOnlyWithLiquidGlass() throws {
        let (store, _, more, menu) = menu()
        defer { withExtendedLifetime(more) {} }
        guard #available(macOS 26, *) else {
            #expect(menu.item(withTitle: "Background") == nil)
            return
        }
        let backgrounds = try #require(menu.item(withTitle: "Background")?.submenu)
        try choose(backgrounds.items.last)
        #expect(store.popoverBackground == .solid)
        try choose(backgrounds.items.first)
        #expect(store.popoverBackground == .liquidGlass)
    }

    @Test func launchAtLoginTogglesAndOffersSettingsAfterAFailure() throws {
        let (_, state, first, menu) = menu()
        defer { withExtendedLifetime(first) {} }
        let launch = try #require(menu.item(withTitle: "Launch at Login"))
        #expect(launch.state == .off)
        try choose(launch)
        #expect(service.registerCalls == 1)
        #expect(state.launchAtLogin.status == .enabled)

        service.unregisterError = NSError(domain: "test", code: 1)
        state.launchAtLogin.toggle()
        let more = MoreMenu(store: CountdownStore(defaults: defaults), state: state)
        let failed = more.make()
        #expect(failed.item(withTitle: "Launch at Login")?.state == .on)
        try choose(failed.item(withTitle: "Login Items Settings…"))
        #expect(service.settingsCalls == 1)
        withExtendedLifetime(more) {}

        service.status = .requiresApproval
        #expect(more.make().item(withTitle: "Launch at Login")?.state == .mixed)
    }

    @Test func aboutAsksTheStatusItem() throws {
        let (_, _, more, menu) = menu()
        let shown = Calls<Void>()
        more.showAbout = { shown.record(()) }
        try choose(menu.item(withTitle: "About Days Until"))
        #expect(shown.values.count == 1)
        // Quit is there, and left alone.
        #expect(menu.item(withTitle: "Quit Days Until")?.keyEquivalent == "q")
        withExtendedLifetime(more) {}
    }

    @Test func withoutACountdownThereIsNothingToEditOrDelete() throws {
        let store = CountdownStore(defaults: defaults)
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: service))
        let menu = MoreMenu(store: store, state: state).make()
        #expect(menu.item(withTitle: "Edit Countdown…")?.isEnabled == false)
        #expect(menu.item(withTitle: "Delete Countdown…")?.isEnabled == false)
        #expect(menu.item(withTitle: "Menu Bar") != nil)
        #expect(menu.item(withTitle: "About Days Until")?.isEnabled == true)
    }

    @Test func aNewInstallLeavesLaunchAtLoginToTheForm() throws {
        let store = CountdownStore(defaults: defaults)
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: service))
        let more = MoreMenu(store: store, state: state)
        #expect(more.make().item(withTitle: "Launch at Login") == nil)
        store.countdown = countdown
        store.countdown = nil
        // Deleted: the form no longer offers it, so the menu does.
        #expect(more.make().item(withTitle: "Launch at Login") != nil)
    }

    @Test func onTheDayTheStylesPreviewToday() throws {
        let store = CountdownStore(defaults: defaults)
        store.countdown = Countdown(name: "Trip", icon: .default, targetDate: Date().addingTimeInterval(-1),
                                    showsTime: true, place: nil, startDate: Date().addingTimeInterval(-86_400))
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: service))
        let styles = try #require(MoreMenu(store: store, state: state).make().item(withTitle: "Menu Bar")?.submenu)
        #expect(styles.items.first?.attributedTitle?.string.hasSuffix("\tToday") == true)
    }
}

@Suite @MainActor
struct AboutPanelTests {
    @Test func namesTheAppAndItsLicence() throws {
        let options = StatusItemController.aboutPanelOptions
        // Its display name, not the target's "DaysUntil".
        #expect(options[.applicationName] as? String == "Days Until")
        let copyright = try #require(options[NSApplication.AboutPanelOptionKey(rawValue: "Copyright")] as? String)
        #expect(copyright.hasPrefix("Copyright © 2026 Yinfeng Lu\n"))
        #expect(copyright.hasSuffix("Free software under the GNU GPL v3 or later."))
    }
}
