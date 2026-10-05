import AppKit
import SwiftUI

/// A view in a borderless window far off screen, which never becomes key or activates the app, so
/// tests can lay it out, draw it and send it keys without anything showing on the Mac's screen.
@MainActor
final class OffscreenHost {
    let window: NSWindow

    init<Content: View>(_ content: Content, size: CGSize = CGSize(width: 340, height: 600)) {
        window = SilentWindow(
            contentRect: CGRect(origin: CGPoint(x: -30000, y: -30000), size: size),
            styleMask: .borderless, backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content)
        window.orderFrontRegardless()
        settle()
        // A field focused as the view appears takes the keyboard a turn or two later, and SwiftUI's
        // focus follows it a turn after that.
        for _ in 0..<10 where editor == nil {
            settle(0.02)
        }
        settle()
    }

    /// Lets SwiftUI catch up: its focus and `onChange` run a turn of the run loop late.
    func settle(_ seconds: TimeInterval = 0.05) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
        window.contentView?.layoutSubtreeIfNeeded()
    }

    /// A key press, as the app's local key monitors see it.
    func press(_ keyCode: UInt16, _ characters: String = "", modifiers: NSEvent.ModifierFlags = []) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode
        )!
        NSApp.sendEvent(event)
        settle()
    }

    /// Typing into the focused text field, as an input method would.
    func type(_ text: String) {
        (window.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        settle()
    }

    /// The text field with the keyboard, if any.
    var editor: NSTextView? { window.firstResponder as? NSTextView }

    /// Every view of a kind inside the window.
    func views<V: NSView>(_ type: V.Type) -> [V] {
        func walk(_ view: NSView) -> [V] { ((view as? V).map { [$0] } ?? []) + view.subviews.flatMap(walk) }
        return window.contentView.map(walk) ?? []
    }

    var fittingSize: CGSize { window.contentView?.fittingSize ?? .zero }

    func close() {
        window.orderOut(nil)
        window.close()
    }

    static let left: UInt16 = 123
    static let right: UInt16 = 124
    static let down: UInt16 = 125
    static let up: UInt16 = 126
    static let pageUp: UInt16 = 116
    static let pageDown: UInt16 = 121
    static let returnKey: UInt16 = 36
    static let escape: UInt16 = 53
    static let t: UInt16 = 17
}

/// Keys nothing takes end here instead of beeping on the Mac running the tests.
private final class SilentWindow: NSWindow {
    override func noResponder(for eventSelector: Selector) {}
    override func cancelOperation(_ sender: Any?) {}
}

/// What a view under test called back with.
@MainActor
final class Calls<Value> {
    var values: [Value] = []
    func record(_ value: Value) { values.append(value) }
}
