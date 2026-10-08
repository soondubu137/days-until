import AppKit
import Combine
import SwiftUI

/// The menu bar item and the popover it opens.
final class StatusItemController: NSObject {
    private let store: CountdownStore
    private let clock: MenuBarClock
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let content: NSHostingController<PopoverView>
    /// The popover, a panel rather than an NSPopover; see `MenuBarPanel`.
    private let panel: MenuBarPanel
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
    /// Set when the popover closes for the About panel or Sparkle's window, which need the app to stay
    /// active.
    private var isClosingForWindow = false
    /// Set while Sparkle's windows have the app in the Dock.
    private var isShowingSparkle = false
    /// The screen Sparkle's windows go on: the popover's, where the person asked for them. Sparkle
    /// centres each window on whichever screen is the main one as the window is made, which with two
    /// displays can be the other one.
    private var sparkleScreen: NSScreen?
    /// Sparkle's windows already put on that screen, so one moved by hand stays where it was moved.
    private var placedSparkleWindows: Set<ObjectIdentifier> = []
    /// AppKit makes a new About panel each time after the last one closes.
    private weak var aboutPanel: NSWindow?
    private var aboutPanelClosing: AnyCancellable?

    init(store: CountdownStore, updates: Updates? = nil, milestones: MilestoneNotifications? = nil) {
        self.store = store
        clock = MenuBarClock(store: store)
        popoverState = PopoverState(store: store, updates: updates, milestones: milestones)
        moreMenu = MoreMenu(store: store, state: popoverState)
        content = NSHostingController(rootView: PopoverView(store: store, state: popoverState, makeMenu: moreMenu.make))
        content.sizingOptions = .preferredContentSize
        panel = MenuBarPanel(content: content.view)
        super.init()
        moreMenu.showAbout = { [weak self] in self?.showAbout() }
        if let updates {
            updates.canRelaunch = { [weak self] in
                guard let self else { return true }
                return !panel.isVisible && !popoverState.holdsAnEdit
            }
            updates.willShowSparkle = { [weak self] in self?.makeWayForSparkle() }
            updates.didFinishSparkle = { [weak self] in self?.sparkleFinished() }
        }
        // The system's menu bar menus fade out after Esc. See `fadeOut()`.
        panel.onCancel = { [weak self] in
            guard let self, fadeOutID == nil else { return }
            fadeOut()
        }

        statusItem.autosaveName = "DaysUntil"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(clickItem)
        // Clicks on the item open and close the popover on mouse down, as the system's items do,
        // rather than when the button's click ends, which would clear the item's highlight just after
        // the popover opened. They're all taken here, with the popover open too: the button drops the
        // second click of a double click if the mouse is already up when it gets it, so a quick second
        // click on the item left the popover open.
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, isClickOnItem(event) else { return event }
            clickItem()
            return nil
        }

        // A click in another app makes the app inactive, which closes the popover.
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
                // A click on the item while a menu is open ends the menu, which keeps the click, so
                // the click monitor never sees it. The popover still closes, as without the menu.
                // Tracking ends once the menu has faded out, by when the click's mouse up is usually
                // the current event.
                if let event = NSApp.currentEvent, event.type == .leftMouseDown || event.type == .leftMouseUp,
                   event.window === statusItem.button?.window {
                    clickItem()
                }
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)
            .sink { [weak self] notification in
                guard let window = notification.object as? NSWindow else { return }
                self?.placeSparkleWindow(window)
            }
            .store(in: &subscriptions)

        // The item grows to the left as its text does, from `48d` to `6d 14h`, and moves when the
        // items beside it change. The popover moves with it, so its left edge stays in line.
        NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)
            .merge(with: NotificationCenter.default.publisher(for: NSWindow.didResizeNotification))
            .sink { [weak self] notification in
                guard let self, panel.isVisible, notification.object as? NSWindow === statusItem.button?.window else { return }
                _ = placePanel()
            }
            .store(in: &subscriptions)

        clock.$text.combineLatest(store.$countdown)
            .sink { [weak self] text, countdown in
                guard let button = self?.statusItem.button else { return }
                MenuBarLabel(icon: countdown?.icon, text: text).apply(to: button)
            }
            .store(in: &subscriptions)
    }

    /// Opens the popover as soon as the item has its place in the menu bar, which takes a moment
    /// at launch. The popover is placed under wherever the item is.
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

    /// After a click on the desktop widget or a milestone: the popover opens, or stays open if it's
    /// fading out.
    func open() {
        if !panel.isVisible {
            showPopoverOnceInPlace()
        } else if fadeOutID != nil {
            fadeOutID = nil
            restoreOpacity()
            updateHighlight()
        }
    }

    /// ⌘E, while the popover shows the countdown.
    @objc func editCountdown() {
        guard panel.isVisible, !popoverState.isEditing else { return }
        popoverState.edit()
    }

    /// The standard About panel, from the ••• menu: the icon, the name, the version and build, and the
    /// copyright. The popover closes first.
    private func showAbout() {
        if panel.isVisible {
            isClosingForWindow = true
            closeAtOnce()
        }
        let shown = Set(NSApp.windows.filter(\.isVisible).map(\.windowNumber))
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: Self.aboutPanelOptions)
        if let about = NSApp.windows.first(where: { $0.isVisible && !shown.contains($0.windowNumber) }) {
            aboutPanel = about
            // Closing it hands the keyboard back to the app that had it, as closing the popover does.
            aboutPanelClosing = NotificationCenter.default.publisher(for: NSWindow.willCloseNotification, object: about)
                .sink { [weak self] _ in
                    guard let self, NSApp.isActive, !panel.isVisible else { return }
                    NSApp.hide(nil)
                }
        }
        // Where the window server turns the app's activation down, the About panel would open behind the
        // app in front.
        aboutPanel?.orderFrontRegardless()
    }

    /// Before Sparkle's window, after Details or Check for Updates…. The popover closes first, as for
    /// About, and the app joins the Dock and ⌘-Tab while Sparkle's windows are open, so one can't get
    /// lost behind other windows.
    private func makeWayForSparkle() {
        sparkleScreen = panel.isVisible ? panel.screen : statusItem.button?.window?.screen
        if panel.isVisible {
            isClosingForWindow = true
            closeAtOnce()
        }
        isShowingSparkle = true
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Out of the Dock again once Sparkle's done, handing the keyboard back as closing the About panel
    /// does.
    private func sparkleFinished() {
        guard isShowingSparkle else { return }
        isShowingSparkle = false
        sparkleScreen = nil
        placedSparkleWindows = []
        NSApp.setActivationPolicy(.accessory)
        if NSApp.isActive, !panel.isVisible, aboutPanel?.isVisible != true {
            NSApp.hide(nil)
        }
    }

    /// Moves a window of Sparkle's to the popover's screen the first time it becomes key, which it does
    /// as it opens.
    private func placeSparkleWindow(_ window: NSWindow) {
        guard isShowingSparkle, let screen = sparkleScreen, window !== panel, window !== aboutPanel,
              placedSparkleWindows.insert(ObjectIdentifier(window)).inserted,
              window.screen?.frame != screen.frame else { return }
        window.setFrameOrigin(Self.centred(window.frame.size, in: screen.visibleFrame))
    }

    /// Where `NSWindow.center()` would put a window of `size` on a screen: centred across, and a little
    /// above the middle.
    static func centred(_ size: CGSize, in visible: CGRect) -> CGPoint {
        CGPoint(x: (visible.midX - size.width / 2).rounded(), y: (visible.minY + (visible.height - size.height) * 2 / 3).rounded())
    }

    static var aboutPanelOptions: [NSApplication.AboutPanelOptionKey: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        let copyright = info["NSHumanReadableCopyright"] as? String ?? ""
        return [
            // The panel would show CFBundleName, the target's "DaysUntil".
            .applicationName: info["CFBundleDisplayName"] as? String ?? "",
            // A key AppKit reads but has no constant for. The licence goes under the copyright.
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"):
                copyright + "\n" + String(localized: "Free software under the GNU GPL v3 or later."),
        ]
    }

    /// ⌘-drag is left alone, for rearranging the menu bar.
    private func isClickOnItem(_ event: NSEvent) -> Bool {
        event.type == .leftMouseDown && event.window === statusItem.button?.window
            && !event.modifierFlags.contains(.command)
    }

    /// Also the button's action, which accessibility clients still press. Clicks never get to it.
    @objc private func clickItem() {
        if !panel.isVisible {
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
        guard placePanel() else { return }
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
        panel.orderFrontRegardless()
        // The window server often turns this app's activation down. After a click on the item,
        // AppKit sends the request with no time of its own, so it's refused as stale once another app
        // has had input or been activated, and always after a launch in the background. The panel is
        // non-activating, so it takes the keyboard as the key window whether or not the app is active.
        panel.makeKey()
        // Still activated where the window server allows it, so that another app becoming active
        // closes the popover, and closing it hands the keyboard back. The cooperative `activate()`
        // of macOS 14 leaves the app inactive after a click on the item.
        NSApp.activate(ignoringOtherApps: true)
        updateHighlight()
    }

    /// Sizes the popover to its content and puts it under the item: its top against the menu bar, and
    /// its left edge in line with the item's highlight capsule, which reaches 2 pt past the item, kept
    /// on the item's screen. While it's open, the content's size constraints resize it as the content
    /// changes, keeping its top edge in place. Also where the item is, for the confetti on the day
    /// itself, which is off-centre when the item is near the screen's edge.
    private func placePanel() -> Bool {
        guard let button = statusItem.button, let itemWindow = button.window, let screen = itemWindow.screen else {
            return false
        }
        let size = content.preferredContentSize
        let item = itemWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let visible = screen.visibleFrame
        // The visible frame stops under the menu bar's 1 pt bottom edge. With the menu bar hidden
        // until the pointer reaches it, the item's bottom edge is the menu bar's.
        let top = min(itemWindow.frame.minY, visible.maxY)
        let x = min(max(item.minX - 2, visible.minX), visible.maxX - size.width)
        panel.setFrame(NSRect(x: x, y: top - size.height, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
        popoverState.itemX = item.midX - x
        return true
    }

    /// The system's items sit on a highlight capsule while their menu is open, and lose it, without
    /// fading, as soon as the menu starts to fade out.
    private func updateHighlight() {
        statusItem.button?.highlight(panel.isVisible && fadeOutID == nil)
    }

    /// After a click anywhere else.
    private func closeAtOnce() {
        guard panel.isVisible else { return }
        close()
    }

    /// Closes the popover, ending an open menu without its fade. The click that opened a menu can come
    /// here too, just after the menu opens, so clicks on the popover are left alone, and so are clicks
    /// on the item, which the item's window can pass on, since the click monitor takes those.
    private func clickInOtherApp(_ event: NSEvent) {
        guard panel.isVisible else { return }
        let location = event.window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow
        guard !panel.frame.contains(location),
              !(statusItem.button?.window?.frame.contains(location) ?? false) else { return }
        openMenu?.cancelTrackingWithoutAnimation()
        isClosingForOtherApp = true
        closeAtOnce()
    }

    /// Closes the popover the way the system's menu bar menus close, as measured on Wi-Fi, Sound and
    /// Battery in macOS 26: after Esc or a click on the item they fade out, window opacity only,
    /// linear, over 0.24 s; after a click anywhere else they vanish at once.
    private func fadeOut() {
        let id = UUID()
        fadeOutID = id
        updateHighlight()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .linear)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated { self?.finishFadeOut(id) }
        }
    }

    private func finishFadeOut(_ id: UUID) {
        guard fadeOutID == id else { return }
        close()
    }

    /// Full opacity at once, stopping a fade on the way.
    private func restoreOpacity() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
    }

    private func close() {
        fadeOutID = nil
        panel.orderOut(nil)
        popoverState.isShown = false
        if let otherAppClickMonitor {
            NSEvent.removeMonitor(otherAppClickMonitor)
            self.otherAppClickMonitor = nil
        }
        updateHighlight()
        // The popover keeps its window for the next time it opens.
        restoreOpacity()
        // Keep an unfinished draft when the popover is dismissed. Only Cancel discards it.
        // Closed from the item or with Esc, the app would stay active with no window to type into.
        // Hiding it hands the keyboard back to the app that had it before. A click in another app
        // makes that app active instead, and hiding on the way would hand the keyboard past it.
        // Hiding would take the About panel or Sparkle's window with it.
        if NSApp.isActive, !isClosingForOtherApp, !isClosingForWindow, !isShowingSparkle {
            NSApp.hide(nil)
        }
        isClosingForOtherApp = false
        isClosingForWindow = false
    }
}
