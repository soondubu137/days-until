import AppKit
import ServiceManagement
import Testing
@testable import DaysUntil

/// Deleting the countdown from the ••• menu: the popover asks first, then it's back to no countdown,
/// with Undo until the popover closes, and without the new install's greeting or launch-at-login offer.
@Suite @MainActor
struct DeleteCountdownTests {
    let defaults: UserDefaults = MemoryDefaults()
    let countdown = Countdown(name: "Trip", icon: .symbol("airplane"), targetDate: Date().addingTimeInterval(86400 * 30),
                              showsTime: false, place: nil, startDate: Date())

    @Test func menuAsksBeforeDeleting() throws {
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub()))
        let more = MoreMenu(store: store, state: state)
        let menu = more.make()
        #expect(menu.items.map(\.title).prefix(2) == ["Edit Countdown…", "Delete Countdown…"])
        let delete = try #require(menu.items.first { $0.title == "Delete Countdown…" })
        NSApp.sendAction(delete.action!, to: delete.target, from: delete)
        #expect(state.isConfirmingDelete)
        #expect(store.countdown == countdown)
        #expect(!state.isEditing)

        state.delete()
        #expect(!state.isConfirmingDelete)
        #expect(store.countdown == nil)
        #expect(state.isEditing)
        #expect(state.deleted == countdown)
        #expect(state.draft.name.isEmpty)
        #expect(CountdownStore(defaults: defaults).countdown == nil)
    }

    @Test func cancelKeepsTheCountdown() {
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub()))
        state.confirmDelete()
        state.cancelDelete()
        #expect(!state.isConfirmingDelete)
        #expect(store.countdown == countdown)
        #expect(!state.isEditing)
        #expect(state.deleted == nil)
    }

    @Test func closingThePopoverCancelsTheQuestion() {
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub()))
        state.isShown = true
        state.confirmDelete()
        state.isShown = false
        #expect(!state.isConfirmingDelete)
        #expect(store.countdown == countdown)
    }

    @Test func undoRestoresTheCountdown() {
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub()))
        state.isShown = true
        state.delete()
        state.undoDelete()
        #expect(store.countdown == countdown)
        #expect(!state.isEditing)
        #expect(state.deleted == nil)
        #expect(CountdownStore(defaults: defaults).countdown == countdown)
    }

    @Test func undoEndsWhenThePopoverCloses() {
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub()))
        state.isShown = true
        state.delete()
        state.isShown = false
        #expect(state.deleted == nil)
        state.undoDelete()
        #expect(store.countdown == nil)
        #expect(state.isEditing)
    }

    @Test func aDeletedCountdownStillCountsAsSetUp() {
        let store = CountdownStore(defaults: defaults)
        #expect(!store.isSetUp)
        store.countdown = countdown
        store.countdown = nil
        #expect(store.isSetUp)
        #expect(CountdownStore(defaults: defaults).isSetUp)
    }

    @Test func aCountdownSavedBeforeTheFlagCountsAsSetUp() throws {
        defaults.set(try JSONEncoder().encode(countdown), forKey: "countdown")
        let store = CountdownStore(defaults: defaults)
        #expect(store.isSetUp)
        store.countdown = nil
        #expect(CountdownStore(defaults: defaults).isSetUp)
    }

    @Test func theNextCountdownLeavesLaunchAtLoginAlone() {
        let service = LoginServiceStub()
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        let state = PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: service))
        state.delete()
        #expect(state.draft.openAtLogin)
        state.save(countdown)
        #expect(service.registerCalls == 0)
        #expect(service.unregisterCalls == 0)
        #expect(state.deleted == nil)
        #expect(!state.isEditing)
    }
}
