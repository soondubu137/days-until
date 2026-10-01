import AppKit

/// What the menu bar item shows: the countdown's icon plus text whose precision depends on how
/// close the moment is. See docs/DESIGN.md, "Menu bar item".
///
/// The label is drawn as one image rather than set as the button's image and title. The menu bar
/// centres a symbol's whole image, margins included, so the icon hung below the text, and it spaced
/// the two by each symbol's own margins. Here the text's cap height sits on the menu bar's midline,
/// the icon sits on the text's baseline the way SF Symbols do in a line of text, and every gap is
/// measured between what's actually drawn.
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
        let line = words.map { Self.line($0, units: isCountdown) }
        if text == .today {
            button.image = Self.todayCapsule(icon: Icon(icon ?? .default), line: line)
        } else {
            // With nothing set yet, the item asks for what it needs.
            button.image = Self.label(icon: Icon(icon ?? .symbol("calendar.badge.plus")), line: line)
        }
        button.title = ""
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(words.map { String(localized: "Days Until: \($0)") } ?? String(localized: "Days Until"))
    }

    // MARK: - Metrics

    private static let font = NSFont.menuBarFont(ofSize: 0)
    /// The menu bar centres the image vertically, so its middle is the bar's midline. The system's
    /// selection capsule is this tall too.
    private static let height: CGFloat = 22
    /// Between the icon and the text, measured between what's drawn.
    private static let iconGap: CGFloat = 5
    /// Around what's drawn, inside the button's own margins. It leaves the icon as far from the next
    /// item as the system's icons are from each other.
    private static let margin: CGFloat = 2
    /// The space between `48d` and `10h`: narrower than a word space, so the units read as one
    /// figure and stay closer to each other than to the icon.
    private static let unitSpace: CGFloat = 3
    /// Around the icon and "Today" inside the accent capsule.
    private static let capsulePadding: CGFloat = 7

    // MARK: - Drawing

    /// The icon and text in the menu bar's colour. A template image, unless the icon is an emoji,
    /// which keeps its own colours: then the text is drawn in the label colour, which the menu bar
    /// renders exactly as it does template images.
    private static func label(icon: Icon, line: CTLine?) -> NSImage {
        let layout = Layout(icon: icon, line: line, padding: margin)
        let image = NSImage(size: NSSize(width: layout.width, height: height), flipped: false) { _ in
            layout.draw(color: icon.isTemplate ? .black : .labelColor)
            return true
        }
        image.isTemplate = icon.isTemplate
        return image
    }

    /// The day itself: the icon and "Today" in white on an accent capsule, as tall as the system's
    /// selection capsule. It's drawn when shown, so it takes the accent colour the Mac has then.
    private static func todayCapsule(icon: Icon, line: CTLine?) -> NSImage {
        let layout = Layout(icon: icon, line: line, padding: capsulePadding)
        let image = NSImage(size: NSSize(width: layout.width, height: height), flipped: false) { rect in
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2).fill()
            layout.draw(color: .white, iconTint: .white)
            return true
        }
        image.isTemplate = false
        return image
    }

    /// The text as one line, drawn in the context's fill colour. In countdown text, the units are
    /// set closer than words. Digits keep their natural widths, which change the text at most once
    /// an hour, except in a ticking clock (`13:42:07`), where they're fixed-width so the seconds
    /// don't shift everything after them.
    private static func line(_ words: String, units: Bool) -> CTLine {
        let fromContext = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)
        guard units else {
            return CTLineCreateWithAttributedString(NSAttributedString(string: words, attributes: [.font: font, fromContext: true]))
        }
        let tabular = NSFont.monospacedDigitSystemFont(ofSize: font.pointSize, weight: .regular)
        let wordSpace = NSAttributedString(string: " ", attributes: [.font: font]).size().width
        let text = NSMutableAttributedString()
        for (index, unit) in words.split(separator: " ").enumerated() {
            if index > 0 {
                text.append(NSAttributedString(string: " ", attributes: [.font: font, .kern: unitSpace - wordSpace]))
            }
            text.append(NSAttributedString(string: String(unit), attributes: [.font: unit.contains(":") ? tabular : font]))
        }
        text.addAttribute(fromContext, value: true, range: NSRange(location: 0, length: text.length))
        return CTLineCreateWithAttributedString(text)
    }

    /// Where the icon and text go in an image `height` tall: the text's cap height centred, the
    /// icon on the same baseline, `padding` around what's drawn, and `iconGap` between the two.
    private struct Layout {
        let icon: Icon
        let line: CTLine?
        let iconX: CGFloat
        let textX: CGFloat
        let width: CGFloat

        init(icon: Icon, line: CTLine?, padding: CGFloat) {
            self.icon = icon
            self.line = line
            guard let line else {
                width = (icon.ink.width + 2 * padding).rounded(.up)
                iconX = (width - icon.ink.width) / 2 - icon.ink.minX
                textX = 0
                return
            }
            iconX = padding - icon.ink.minX
            let ink = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            textX = padding + icon.ink.width + iconGap - ink.minX
            // The text's advance rather than its ink sets the right edge, so the item doesn't change
            // width as the seconds tick.
            width = (textX + CTLineGetTypographicBounds(line, nil, nil, nil) + padding).rounded(.up)
        }

        func draw(color: NSColor, iconTint: NSColor? = nil) {
            guard let context = NSGraphicsContext.current?.cgContext else { return }
            // On whole pixels, so the text's horizontal strokes stay sharp. The menu bar puts the
            // image's edges on whole pixels.
            let scale = max(context.userSpaceToDeviceSpaceTransform.a, 1)
            func snap(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
            let baseline = snap((height - font.capHeight) / 2)

            icon.draw(at: NSPoint(x: iconX, y: snap(baseline + icon.originFromBaseline)), tint: iconTint)
            if let line {
                color.setFill()
                context.textMatrix = .identity
                context.textPosition = CGPoint(x: textX, y: baseline)
                CTLineDraw(line, context)
            }
        }
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
