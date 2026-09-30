import AppKit
import Combine
import SwiftUI

/// The menu bar item and the popover it opens.
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let store: CountdownStore
    private let clock: MenuBarClock
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let popoverState: PopoverState
    private let moreMenu: MoreMenu
    private var subscriptions: Set<AnyCancellable> = []

    init(store: CountdownStore) {
        self.store = store
        clock = MenuBarClock(store: store)
        popoverState = PopoverState(store: store)
        moreMenu = MoreMenu(store: store, state: popoverState)
        super.init()

        let content = NSHostingController(rootView: PopoverView(store: store, state: popoverState, makeMenu: moreMenu.make))
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient
        popover.delegate = self
        if #available(macOS 14, *) {
            // The content reaches under the arrow, so a solid background covers the whole popover,
            // arrow included. The content itself keeps to the safe area, where it would be anyway.
            // Set once: changing it while the popover is shown leaves the popover the wrong size.
            // On macOS 13 the arrow keeps the system's material.
            popover.hasFullSizeContent = true
        }

        statusItem.autosaveName = "DaysUntil"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)

        // The popover would otherwise take the menu bar's appearance, which on macOS 26 follows the
        // wallpaper rather than Light or Dark Mode.
        NSApp.publisher(for: \.effectiveAppearance)
            .sink { [weak self] appearance in self?.popover.appearance = appearance }
            .store(in: &subscriptions)

        clock.$text.combineLatest(store.$countdown)
            .sink { [weak self] text, countdown in
                guard let button = self?.statusItem.button else { return }
                MenuBarLabel(icon: countdown?.icon, text: text).apply(to: button)
            }
            .store(in: &subscriptions)
    }

    /// Opens the popover as soon as the item has its place in the menu bar, which takes a moment
    /// at launch. The popover is placed under wherever the item is when it opens.
    func showPopoverOnceInPlace(attempts: Int = 30) {
        if let window = statusItem.button?.window, let screen = window.screen,
           window.frame.height > 0, abs(window.frame.maxY - screen.frame.maxY) < 1 {
            showPopover()
        } else if attempts > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.showPopoverOnceInPlace(attempts: attempts - 1)
            }
        }
    }

    /// ⌘E, while the popover shows the countdown.
    @objc func editCountdown() {
        guard popover.isShown, !popoverState.isEditing else { return }
        popoverState.edit()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // Without a Dock icon the app isn't active, and the form's text fields need it to be.
        // The cooperative `activate()` of macOS 14 leaves the app inactive after a click on the item.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverWillShow(_ notification: Notification) {
        popoverState.isShown = true
    }

    func popoverDidClose(_ notification: Notification) {
        popoverState.isShown = false
        // An edit left open is dropped, so the popover reopens on the countdown.
        if store.countdown != nil {
            popoverState.isEditing = false
        }
        // Closed from the item or with Esc, the app would stay active with no window to type into.
        // Hiding it hands the keyboard back to the app that had it before.
        if NSApp.isActive {
            NSApp.hide(nil)
        }
    }
}
