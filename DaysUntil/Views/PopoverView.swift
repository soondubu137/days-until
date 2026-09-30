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
    @Published var draft = Draft()

    private let store: CountdownStore

    init(store: CountdownStore) {
        self.store = store
        // With nothing to count down to yet, go straight to the form.
        isEditing = store.countdown == nil
    }

    /// Opens the form on the current countdown.
    func edit() {
        guard let countdown = store.countdown else { return }
        draft = Draft(editing: countdown)
        isEditing = true
    }

    /// Opens the form for the next countdown once one is reached.
    func startOver() {
        guard let countdown = store.countdown else { return }
        draft = Draft(after: countdown)
        isEditing = true
    }

    func cancel() {
        isEditing = false
    }

    func save(_ countdown: Countdown) {
        if store.countdown == nil {
            LaunchAtLogin.set(draft.openAtLogin)
        }
        store.countdown = countdown
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

    var body: some View {
        let background = PopoverBackground.effective(store.popoverBackground)
        Group {
            if let countdown = store.countdown, !state.isEditing {
                CountdownView(countdown: countdown, now: now, makeMenu: makeMenu, onStartOver: state.startOver)
            } else {
                EditView(draft: $state.draft, now: now, isNew: store.countdown == nil, onCancel: state.cancel, onSave: state.save)
            }
        }
        .frame(width: 340)
        .background {
            // Liquid Glass is the popover's own. Solid covers it, arrow included, since the popover's
            // content reaches under the arrow; see `StatusItemController`.
            if background == .solid {
                Color.solidPanel.ignoresSafeArea()
            }
        }
        .environment(\.popoverBackground, background)
        .task(id: state.isShown) {
            while state.isShown, !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(nextTick(after: now).timeIntervalSince(now)))
            }
        }
    }

    /// The next second while the count ticks, otherwise the next minute for the place clocks.
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
