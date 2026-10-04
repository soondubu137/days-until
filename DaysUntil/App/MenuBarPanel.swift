import AppKit

/// The popover's window, shaped and placed like the system's menu bar menus, as measured on Wi-Fi's
/// in macOS 26: no arrow, the top edge against the menu bar, the left edge in line with the item's
/// highlight, and the same rounded corners all round. NSPopover would point an arrow at the item and
/// leave a gap under the menu bar.
final class MenuBarPanel: NSPanel {
    /// Esc, unless the content takes it first.
    var onCancel: () -> Void = {}

    static let cornerRadius: CGFloat = Radius.isTahoe ? 16 : 10

    init(content: NSView) {
        // Non-activating, as NSPopover's own window is, so it can take the keyboard as the key window
        // whether or not the app is active. See `StatusItemController.showPopover()`.
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // The level of the system's own menu bar menus, just under the menu bar.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue - 1)
        collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        animationBehavior = .none
        hidesOnDeactivate = false
        isReleasedWhenClosed = false

        let frame = NSView()
        frame.wantsLayer = true
        frame.layer?.cornerRadius = Self.cornerRadius
        frame.layer?.cornerCurve = .continuous
        frame.layer?.masksToBounds = true
        // Liquid Glass, as NSPopover draws it, under the content rather than around it. The Solid
        // background is the content's own. Before macOS 26 the popover is always Solid.
        if #available(macOS 26, *) {
            let glass = NSGlassEffectView()
            glass.cornerRadius = Self.cornerRadius
            glass.autoresizingMask = [.width, .height]
            frame.addSubview(glass)
        }
        content.autoresizingMask = [.width, .height]
        frame.addSubview(content)
        contentView = frame
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onCancel()
    }
}
