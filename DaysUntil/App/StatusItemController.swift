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
    /// Set while the popover fades out. A new ID for each fade, so one cut short by a click on the
    /// item doesn't close the popover when its time would have been up.
    private var fadeOutID: UUID?
    private var clickMonitor: Any?
    private var otherAppClickMonitor: Any?
    /// A menu opened from the popover, the ••• menu or a text field's, while it's open.
    private var openMenu: NSMenu?
    /// Set when a click in another app closes the popover before the app has become inactive.
    private var isClosingForOtherApp = false

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
        // The system's menu bar menus appear at once, where NSPopover would grow out of the arrow.
        // See `popoverShouldClose(_:)` for how they close.
        popover.animates = false
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
        statusItem.button?.action = #selector(clickItem)
        // Clicks on the item open and close the popover on mouse down, as the system's items do,
        // rather than when the button's click ends, which would clear the item's highlight just after
        // the popover opened. They're all taken here, with the popover open too. The popover's own
        // closing on clicks outside it skips the second click of a double click, and the button drops
        // that click if the mouse is already up when it gets it, so a quick second click on the item
        // left the popover open.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, isClickOnItem(event) else { return event }
            clickItem()
            return nil
        }

        // A click in another app makes the app inactive, and NSPopover closes the popover when it
        // does, but only until a menu has been open in it, the ••• menu or a text field's. After
        // that the popover stayed open, so it's closed here. A click on the item while a menu is
        // open goes to the menu rather than the click monitor, and is taken in `popoverShouldClose(_:)`.
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in self?.closeAtOnce() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didBeginTrackingNotification)
            .sink { [weak self] notification in
                guard let self, openMenu == nil else { return }
                openMenu = notification.object as? NSMenu
            }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: NSMenu.didEndTrackingNotification)
            .sink { [weak self] notification in
                guard let self, notification.object as? NSMenu === openMenu else { return }
                openMenu = nil
            }
            .store(in: &subscriptions)

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

    /// ⌘-drag is left alone, for rearranging the menu bar.
    private func isClickOnItem(_ event: NSEvent) -> Bool {
        event.type == .leftMouseDown && event.window === statusItem.button?.window
            && !event.modifierFlags.contains(.command)
    }

    /// Also the button's action, which accessibility clients still press. Clicks never get to it.
    @objc private func clickItem() {
        if !popover.isShown {
            showPopover()
        } else if fadeOutID == nil {
            fadeOut()
        } else {
            // Clicked again mid-fade, the system's menus reopen at full opacity.
            fadeOutID = nil
            restoreOpacity()
            updateHighlight()
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        // Without a Dock icon the app isn't active, and the form's text fields need it to be.
        // The cooperative `activate()` of macOS 14 leaves the app inactive after a click on the item.
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        updateHighlight()
    }

    /// The system's items sit on a highlight capsule while their menu is open, and lose it, without
    /// fading, as soon as the menu starts to fade out.
    private func updateHighlight() {
        statusItem.button?.highlight(popover.isShown && fadeOutID == nil)
    }

    /// Closes the popover the way the system's menu bar menus close, as measured on Wi-Fi, Sound and
    /// Battery in macOS 26: after Esc or a click on the item they fade out, window opacity only,
    /// linear, over 0.24 s; after a click anywhere else they vanish at once. NSPopover's own animation
    /// would shrink back into the arrow either way.
    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        let event = NSApp.currentEvent
        // A single click on the item comes here before it goes on to the click monitor, which closes
        // the popover. See `init(store:)`. While a menu is open, the menu takes the click instead,
        // and the click monitor never sees it.
        if let event, isClickOnItem(event) {
            if openMenu != nil {
                clickItem()
            }
            return false
        }
        if event?.type == .keyDown {
            if fadeOutID == nil {
                fadeOut()
            }
            return false
        }
        fadeOutID = nil
        return true
    }

    /// After a click anywhere else.
    private func closeAtOnce() {
        guard popover.isShown else { return }
        fadeOutID = nil
        popover.close()
    }

    /// Closes the popover, ending an open menu without its fade. The click that opened a menu can come
    /// here too, just after the menu opens, so clicks on the popover are left alone, and so are clicks
    /// on the item, which the item's window can pass on, since the click monitor takes those.
    private func clickInOtherApp(_ event: NSEvent) {
        guard popover.isShown, let window = popover.contentViewController?.view.window else { return }
        let location = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        guard !window.frame.contains(location),
              !(statusItem.button?.window?.frame.contains(location) ?? false) else { return }
        openMenu?.cancelTrackingWithoutAnimation()
        isClosingForOtherApp = true
        closeAtOnce()
    }

    private func fadeOut() {
        guard let window = popover.contentViewController?.view.window else { return }
        let id = UUID()
        fadeOutID = id
        updateHighlight()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishFadeOut(id) }
        }
    }

    private func finishFadeOut(_ id: UUID) {
        guard fadeOutID == id else { return }
        fadeOutID = nil
        popover.close()
    }

    /// Full opacity at once, stopping a fade on the way.
    private func restoreOpacity() {
        guard let window = popover.contentViewController?.view.window else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            window.animator().alphaValue = 1
        }
    }

    func popoverWillShow(_ notification: Notification) {
        popoverState.isShown = true
        // With a menu open, the app becomes inactive only once the menu has faded out, and a click on
        // a window behind the active app's, Claude's under Xcode's, left the popover open without one.
        // So every click in another app closes the popover, at once, with any menu. Watched only while
        // the popover is open, so clicks elsewhere don't wake the app the rest of the time.
        if otherAppClickMonitor == nil {
            otherAppClickMonitor = NSEvent.addGlobalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                self?.clickInOtherApp(event)
            }
        }
    }

    /// Where the arrow points, for the confetti on the day itself. It's off-centre when the item is
    /// near the screen's edge.
    func popoverDidShow(_ notification: Notification) {
        guard let button = statusItem.button, let itemWindow = button.window,
              let content = popover.contentViewController?.view, let window = content.window else { return }
        let item = itemWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let frame = window.convertToScreen(content.convert(content.bounds, to: nil))
        popoverState.arrowX = item.midX - frame.minX
    }

    func popoverDidClose(_ notification: Notification) {
        popoverState.isShown = false
        if let otherAppClickMonitor {
            NSEvent.removeMonitor(otherAppClickMonitor)
            self.otherAppClickMonitor = nil
        }
        updateHighlight()
        // The popover keeps its window for the next time it opens.
        restoreOpacity()
        // An edit left open is dropped, so the popover reopens on the countdown.
        if store.countdown != nil {
            popoverState.isEditing = false
        }
        // Closed from the item or with Esc, the app would stay active with no window to type into.
        // Hiding it hands the keyboard back to the app that had it before. A click in another app
        // makes that app active instead, and hiding on the way would hand the keyboard past it.
        if NSApp.isActive, !isClosingForOtherApp {
            NSApp.hide(nil)
        }
        isClosingForOtherApp = false
    }
}
