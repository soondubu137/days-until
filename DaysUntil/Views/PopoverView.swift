import Combine
import SwiftUI

/// What the popover shows. The status item owns it, so it outlives the popover's content between
/// openings. Closing the popover keeps an unfinished edit; Cancel explicitly discards it.
final class PopoverState: ObservableObject {
    /// The popover's clocks tick only while it's on screen.
    @Published var isShown = false {
        didSet {
            if isShown, !oldValue {
                openedAt = Date()
                updates?.popoverOpened()
            }
            if !isShown {
                isConfirmingDelete = false
                deleted = nil
                if oldValue { updates?.popoverClosed() }
            }
        }
    }
    /// When the popover last opened, to tell one opening from the next.
    @Published private(set) var openedAt: Date?
    @Published var isEditing: Bool
    /// The edit form's working copy. Kept non-optional, since the form can still read it during the
    /// update that closes the form.
    @Published var draft = Draft()
    /// The middle of the menu bar item, from the popover's left edge, once it's shown.
    @Published var itemX: CGFloat?
    /// Set while the popover asks whether to delete the countdown. Closing the popover cancels it.
    @Published private(set) var isConfirmingDelete = false
    /// The countdown just deleted, while that can be undone: until the popover closes or a new
    /// countdown starts.
    @Published private(set) var deleted: Countdown?

    private let store: CountdownStore
    let launchAtLogin: LaunchAtLogin
    /// Nil where Sparkle doesn't run, as under the tests.
    let updates: Updates?

    init(store: CountdownStore, launchAtLogin: LaunchAtLogin = LaunchAtLogin(), updates: Updates? = nil) {
        self.launchAtLogin = launchAtLogin
        self.updates = updates
        self.store = store
        // With nothing to count down to yet, go straight to the form.
        isEditing = store.countdown == nil
    }

    /// Whether something typed into the form would be lost if the app relaunched. The form keeps it
    /// while the popover is closed.
    var holdsAnEdit: Bool {
        isEditing && (store.countdown != nil || !draft.name.isEmpty)
    }

    /// Opens the form on the current countdown.
    func edit() {
        guard let countdown = store.countdown else { return }
        draft = Draft(editing: countdown)
        isConfirmingDelete = false
        isEditing = true
    }

    /// Opens the form for the next countdown once one is reached.
    func startOver() {
        guard let countdown = store.countdown else { return }
        draft = Draft(after: countdown)
        isEditing = true
    }

    /// Asks in the popover, in the countdown's place, before `delete()`.
    func confirmDelete() {
        guard store.countdown != nil else { return }
        isConfirmingDelete = true
    }

    func cancelDelete() {
        isConfirmingDelete = false
    }

    /// Back to no countdown, as on a new install, with the chance to undo it.
    func delete() {
        guard let countdown = store.countdown else { return }
        isConfirmingDelete = false
        deleted = countdown
        draft = Draft()
        isEditing = true
        store.countdown = nil
    }

    func undoDelete() {
        guard let deleted else { return }
        store.countdown = deleted
        self.deleted = nil
        isEditing = false
    }

    func cancel() {
        isEditing = false
    }

    func save(_ countdown: Countdown) {
        // Only a new install's form offers launch at login. After that, it's set in the ••• menu.
        if !store.isSetUp {
            launchAtLogin.set(draft.openAtLogin)
        }
        store.countdown = countdown
        deleted = nil
        isEditing = false
    }
}

/// What opens from the menu bar item: the countdown, or the edit form in its place.
struct PopoverView: View {
    @ObservedObject var store: CountdownStore
    @ObservedObject var state: PopoverState
    /// Builds the ••• menu each time it opens, so its previews read the time then.
    let makeMenu: () -> NSMenu
    @State private var now = Date()
    @State private var clockRevision = 0

    private struct TickID: Equatable {
        var shown: Bool
        var editing: Bool
        var target: Date?
        var revision: Int
    }
    /// When the confetti began, while it plays.
    @State private var confetti: Date?
    /// The opening the confetti last played in.
    @State private var celebratedOpening: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let background = PopoverBackground.effective(store.popoverBackground)
        VStack(spacing: 0) {
            if let countdown = store.countdown, !state.isEditing {
                if state.isConfirmingDelete {
                    DeleteConfirmation(countdown: countdown, onCancel: state.cancelDelete, onDelete: state.delete)
                } else {
                    CountdownView(countdown: countdown, now: now, makeMenu: makeMenu, onStartOver: state.startOver)
                }
            } else {
                EditView(
                    draft: $state.draft, now: now, isNew: store.countdown == nil, makeMenu: makeMenu, offersLaunchAtLogin: !store.isSetUp,
                    deletedName: state.deleted?.name, onUndoDelete: state.undoDelete, onCancel: state.cancel, onSave: state.save
                )
            }
            LaunchAtLoginFeedback(launchAtLogin: state.launchAtLogin)
            if let updates = state.updates {
                UpdateFeedback(updates: updates)
            }
        }
        .frame(width: 340)
        .background {
            // Liquid Glass is the popover's own. Solid covers it; see `MenuBarPanel`.
            if background == .solid {
                Color.solidPanel.ignoresSafeArea()
            }
        }
        .overlay {
            // Over the whole popover, and never in the way of a click.
            if let confetti {
                ConfettiView(start: confetti, originX: state.itemX)
                    .id(confetti)
                    .ignoresSafeArea()
            }
        }
        .environment(\.popoverBackground, background)
        .onAppear {
            state.launchAtLogin.refresh()
            celebrate()
        }
        .onChange(of: state.openedAt) { _ in celebrate() }
        .onChange(of: showsTheDay) { _ in celebrate() }
        .onChange(of: state.isShown) { isShown in
            if isShown {
                state.launchAtLogin.refresh()
                now = Date()
                state.draft.changeTimeZone(to: .current)
            } else { confetti = nil }
        }
        .task(id: confetti) {
            guard confetti != nil else { return }
            do {
                try await Task.sleep(for: .seconds(ConfettiView.duration))
                confetti = nil
            } catch {}
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            state.launchAtLogin.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange).receive(on: DispatchQueue.main)) { _ in
            NSTimeZone.resetSystemTimeZone()
            refreshClock()
        }
        .onReceive(Publishers.MergeMany(
            NotificationCenter.default.publisher(for: .NSSystemClockDidChange),
            NotificationCenter.default.publisher(for: .NSCalendarDayChanged),
            NotificationCenter.default.publisher(for: NSLocale.currentLocaleDidChangeNotification),
            NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
        ).receive(on: DispatchQueue.main)) { _ in refreshClock() }
        .task(id: TickID(shown: state.isShown, editing: state.isEditing, target: store.countdown?.targetDate, revision: clockRevision)) {
            while state.isShown, !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(max(nextTick(after: now).timeIntervalSince(now), 0.001)))
            }
        }
    }

    private func refreshClock() {
        now = Date()
        state.draft.changeTimeZone(to: .current)
        clockRevision += 1 // Cancel any sleep scheduled against the old clock or zone.
    }

    /// Whether the popover is open on the day itself. Read on the Mac's clock, since `now` is still
    /// the last time the popover was open for a moment after it opens.
    private var showsTheDay: Bool {
        guard state.isShown, let countdown = store.countdown else { return false }
        let moment = CountdownMath.moment(of: countdown, calendar: .local)
        return CountdownMath.readout(moment: moment, now: Date(), calendar: .local) == .today
    }

    /// Each time the popover opens on the day itself, and as the clock reaches zero with it open.
    /// An opening can arrive more than once, as the view appears and as the state changes, so it
    /// plays once an opening. With Reduce Motion on, the day passes without confetti.
    private func celebrate() {
        guard showsTheDay, let opening = state.openedAt, opening != celebratedOpening else { return }
        celebratedOpening = opening
        if !reduceMotion {
            confetti = Date()
        }
    }

    /// The next second while the count ticks, otherwise the next minute for the place clocks.
    private func nextTick(after now: Date) -> Date {
        let minute = 60.0
        let nextMinute = Date(timeIntervalSinceReferenceDate: (now.timeIntervalSinceReferenceDate / minute).rounded(.down) * minute + minute)
        if state.isEditing { return Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate.rounded(.down) + 1) }
        guard let countdown = store.countdown else { return nextMinute }
        let moment = CountdownMath.moment(of: countdown, calendar: .local)
        return CountdownMath.nextSecondChange(moment: moment, now: now) ?? nextMinute
    }
}
