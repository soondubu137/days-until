import AppKit

/// What the menu bar item shows: the countdown's icon plus text whose precision depends on how
/// close the moment is. See docs/DESIGN.md, "Menu bar item".
///
/// The text is the button's title, so the menu bar draws it as it draws the clock's: at the same
/// weight and on the same baseline. Drawn into an image, it came out thinner. The icon is an image
/// of its own, placed by what's drawn. The menu bar centres a symbol's whole image, margins
/// included, so the icon hung below the text, and it spaced the two by each symbol's own margins.
/// Here the icon sits on the title's baseline the way SF Symbols do in a line of text, and its gap
/// to the text is measured between what's actually drawn.
struct MenuBarLabel {
    /// Nil while no countdown is set.
    let icon: CountdownIcon?
    let text: CountdownMath.MenuBarText?

    func apply(to button: NSStatusBarButton) {
        let words: String? =
            switch text {
            case nil: String(localized: "Set date")
            case .remaining(let remaining): remaining
            case .today: String(localized: "Today")
            case .iconOnly: nil
            }
        let isCountdown = if case .remaining = text { true } else { false }
        let title = words.map { Self.title($0, units: isCountdown) }
        // With nothing set yet, the item asks for what it needs. On the day itself, the one coloured
        // state, the icon takes the accent.
        button.image = Self.image(
            icon: Icon(icon ?? .symbol("calendar.badge.plus")), title: title,
            tint: text == .today ? .controlAccentColor : nil
        )
        button.attributedTitle = title ?? NSAttributedString()
        button.imagePosition = title == nil ? .imageOnly : .imageLeading
        button.setAccessibilityLabel(words.map { String(localized: "Days Until: \($0)") } ?? String(localized: "Days Until"))
    }

    // MARK: - Metrics

    private static let font = NSFont.menuBarFont(ofSize: 0)
    /// The button's height. The menu bar centres the button, and the image in it, on the bar's
    /// midline.
    private static let height: CGFloat = 22
    /// How far below the midline the menu bar sets a title's baseline, the clock's and the battery's
    /// included.
    private static let titleBaseline: CGFloat = 4
    /// The button's own space between its image and its title.
    private static let titleSpacing: CGFloat = 2
    /// Between the icon and the text, measured between what's drawn.
    private static let iconGap: CGFloat = 5
    /// Around the icon alone, inside the button's own margins. It leaves the icon as far from the
    /// next item as the system's icons are from each other. With a title, the button's margins are
    /// this much wider already.
    private static let margin: CGFloat = 2
    /// The space between `48d` and `10h`: narrower than a word space, so the units read as one
    /// figure and stay closer to each other than to the icon.
    private static let unitSpace: CGFloat = 3

    // MARK: - Drawing

    /// The icon, on the title's baseline and `iconGap` from its first drawn letter. Alone, it's
    /// centred with `margin` on either side. A template image, unless the icon is an emoji,
    /// which keeps its own colours, or a symbol in `tint`. It's drawn when shown, so a tint like the
    /// accent is the one the Mac has then.
    private static func image(icon: Icon, title: NSAttributedString?, tint: NSColor?) -> NSImage {
        let width: CGFloat
        let x: CGFloat
        if let title {
            let textInk = CTLineGetBoundsWithOptions(CTLineCreateWithAttributedString(title), .useGlyphPathBounds)
            let trailing = iconGap - titleSpacing - textInk.minX
            width = (icon.ink.width + trailing).rounded(.up)
            x = width - trailing - icon.ink.maxX
        } else {
            width = (icon.ink.width + 2 * margin).rounded(.up)
            x = (width - icon.ink.width) / 2 - icon.ink.minX
        }
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            // On whole pixels, as the title's baseline is.
            let scale = max(NSGraphicsContext.current?.cgContext.userSpaceToDeviceSpaceTransform.a ?? 1, 1)
            let y = height / 2 - titleBaseline + icon.originFromBaseline
            icon.draw(at: NSPoint(x: x, y: (y * scale).rounded() / scale), tint: tint)
            return true
        }
        image.isTemplate = icon.isTemplate && tint == nil
        return image
    }

    /// The text as the button's title. In countdown text, the units are set closer than words.
    /// Digits keep their natural widths, which change the text at most once an hour, except in a
    /// ticking clock (`13:42:07`), where they're fixed-width so the seconds don't shift everything
    /// after them.
    private static func title(_ words: String, units: Bool) -> NSAttributedString {
        let text = NSMutableAttributedString()
        if units {
            let tabular = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
            let wordSpace = NSAttributedString(string: " ", attributes: [.font: font]).size().width
            for (index, unit) in words.split(separator: " ").enumerated() {
                if index > 0 {
                    text.append(NSAttributedString(string: " ", attributes: [.font: font, .kern: unitSpace - wordSpace]))
                }
                text.append(NSAttributedString(string: String(unit), attributes: [.font: unit.contains(":") ? tabular : font]))
            }
        } else {
            text.append(NSAttributedString(string: words, attributes: [.font: font]))
        }
        return text
    }

    /// The countdown's icon, ready to place: an SF Symbol at the text's size, or an emoji drawn as
    /// an image, with the part of it that's drawn on. Symbols' images have margins that differ from
    /// symbol to symbol.
    private struct Icon {
        let image: NSImage
        /// The drawn part, in the image's coordinates.
        let ink: NSRect
        /// Where the image's bottom goes, from the text's baseline.
        let originFromBaseline: CGFloat
        /// A symbol, drawn in whatever colour it's given. An emoji keeps its own colours.
        let isTemplate: Bool

        private static let configuration = NSImage.SymbolConfiguration(pointSize: font.pointSize, weight: .regular)

        init(_ icon: CountdownIcon) {
            let image: NSImage
            switch icon {
            case .symbol(let name):
                image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
                    .withSymbolConfiguration(Self.configuration)
                    ?? NSImage(size: NSSize(width: font.pointSize, height: font.pointSize))
            case .emoji(let emoji):
                let text = NSAttributedString(string: emoji, attributes: [.font: font])
                image = NSImage(size: text.size(), flipped: false) { _ in
                    text.draw(at: .zero)
                    return true
                }
            }
            let ink = Self.inkCache[icon] ?? Self.inkBounds(of: image)
            Self.inkCache[icon] = ink
            self.image = image
            self.ink = ink
            switch icon {
            case .symbol:
                // A symbol's alignment rect runs from the baseline to the cap height. Sitting on the
                // baseline, it's centred on the text the way Apple drew it to be.
                originFromBaseline = -image.alignmentRect.minY
                isTemplate = true
            case .emoji:
                // An emoji is a picture rather than a letter, so it's centred on the cap height.
                originFromBaseline = font.capHeight / 2 - ink.midY
                isTemplate = false
            }
        }

        /// Draws the icon, a symbol in `tint` if there is one.
        func draw(at origin: NSPoint, tint: NSColor?) {
            let rect = NSRect(origin: origin, size: image.size)
            if isTemplate, let tint {
                image.withSymbolConfiguration(Self.configuration.applying(.init(paletteColors: [tint])))?.draw(in: rect)
            } else {
                image.draw(in: rect)
            }
        }

        private static var inkCache: [CountdownIcon: NSRect] = [:]

        /// The smallest rectangle holding everything `image` draws, found by drawing it.
        private static func inkBounds(of image: NSImage) -> NSRect {
            let scale: CGFloat = 4
            let width = Int((image.size.width * scale).rounded(.up))
            let height = Int((image.size.height * scale).rounded(.up))
            guard width > 0, height > 0, let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return NSRect(origin: .zero, size: image.size) }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            context.scaleBy(x: scale, y: scale)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()

            guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else {
                return NSRect(origin: .zero, size: image.size)
            }
            var minX = width, maxX = -1, minRow = height, maxRow = -1
            for row in 0..<height {
                for x in 0..<width where data[row * width * 4 + x * 4 + 3] > 24 {
                    minX = min(minX, x)
                    maxX = max(maxX, x)
                    minRow = min(minRow, row)
                    maxRow = max(maxRow, row)
                }
            }
            guard maxX >= 0 else { return NSRect(origin: .zero, size: image.size) }
            // The bitmap's first row is the image's top.
            return NSRect(
                x: CGFloat(minX) / scale, y: CGFloat(height - 1 - maxRow) / scale,
                width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxRow - minRow + 1) / scale
            )
        }
    }
}
