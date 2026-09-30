import AppKit

/// What the menu bar item shows: the countdown's icon plus text whose precision depends on how
/// close the moment is.
struct MenuBarLabel {
    /// Nil while no countdown is set.
    let icon: CountdownIcon?
    let text: CountdownMath.MenuBarText?

    /// Tabular digits, so the item doesn't shift as the numbers change.
    private static let font = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular
    )

    func apply(to button: NSStatusBarButton) {
        let words: String? =
            switch text {
            case nil: String(localized: "Set date")
            case .remaining(let remaining): remaining
            case .today: String(localized: "Today")
            case .iconOnly: nil
            }
        switch icon ?? .default {
        case .symbol(let name):
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Days Until")
            button.title = words ?? ""
        case .emoji(let emoji):
            button.image = nil
            button.title = [emoji, words].compactMap(\.self).joined(separator: " ")
        }
        button.font = Self.font
        button.imagePosition = button.title.isEmpty ? .imageOnly : .imageLeading
    }
}
