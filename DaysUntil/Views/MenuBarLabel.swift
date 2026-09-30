import AppKit

/// What the menu bar item shows: the countdown's icon plus text whose precision depends on how
/// close the moment is. Symbols are template images, so they follow the menu bar over any wallpaper.
/// The day itself is the one exception: the item fills with the system accent.
struct MenuBarLabel {
    /// Nil while no countdown is set.
    let icon: CountdownIcon?
    let text: CountdownMath.MenuBarText?

    /// Tabular digits, so the item doesn't shift as the numbers change.
    private static let font = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.menuBarFont(ofSize: 0).pointSize, weight: .regular
    )

    func apply(to button: NSStatusBarButton) {
        button.font = Self.font
        if text == .today {
            button.image = Self.todayCapsule(icon: icon ?? .default)
            button.title = ""
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel(String(localized: "Days Until: Today"))
            return
        }

        let words: String? =
            switch text {
            case nil: String(localized: "Set date")
            case .remaining(let remaining): remaining
            case .today: String(localized: "Today")
            case .iconOnly: nil
            }
        // With nothing set yet, the item asks for what it needs.
        switch icon ?? .symbol("calendar.badge.plus") {
        case .symbol(let name):
            button.image = NSImage(systemSymbolName: name, accessibilityDescription: "Days Until")
            button.title = words ?? ""
        case .emoji(let emoji):
            button.image = nil
            button.title = [emoji, words].compactMap(\.self).joined(separator: " ")
        }
        button.imagePosition = button.title.isEmpty ? .imageOnly : .imageLeading
        button.setAccessibilityLabel(nil)
    }

    /// The icon and "Today" on an accent capsule. It's drawn when shown, so it takes the accent
    /// colour the Mac has then.
    private static func todayCapsule(icon: CountdownIcon) -> NSImage {
        let title = NSAttributedString(string: String(localized: "Today"), attributes: [.font: font, .foregroundColor: NSColor.white])
        let glyph: NSImage? =
            switch icon {
            case .symbol(let name):
                NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)
                        .applying(NSImage.SymbolConfiguration(paletteColors: [.white])))
            case .emoji: nil
            }
        let emoji = if case .emoji(let emoji) = icon {
            NSAttributedString(string: emoji, attributes: [.font: font])
        } else {
            nil as NSAttributedString?
        }

        let height = min(NSStatusBar.system.thickness - 2, 22)
        let padding: CGFloat = 7
        let gap: CGFloat = 5
        let iconWidth = glyph?.size.width ?? emoji?.size().width ?? 0
        let size = NSSize(width: ceil(padding + iconWidth + gap + title.size().width + padding), height: height)

        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            if let glyph {
                glyph.draw(in: NSRect(
                    x: padding, y: (height - glyph.size.height) / 2, width: glyph.size.width, height: glyph.size.height
                ))
            } else if let emoji {
                emoji.draw(at: NSPoint(x: padding, y: (height - emoji.size().height) / 2))
            }
            title.draw(at: NSPoint(x: padding + iconWidth + gap, y: (height - title.size().height) / 2))
            return true
        }
        image.isTemplate = false
        return image
    }
}
