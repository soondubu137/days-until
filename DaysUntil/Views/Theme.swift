import SwiftUI

// The design's colour tokens and shapes. Everything macOS draws itself is left to it: menus,
// switches, buttons, the menu bar and the accent, which is always the person's own.

extension Color {
    /// The solid popover's panel, used on macOS 13 to 15 and when Solid is picked on macOS 26.
    static let solidPanel = Color(light: NSColor(white: 0.953, alpha: 1), dark: NSColor(srgbRed: 0.165, green: 0.165, blue: 0.173, alpha: 1))

    /// Icon wells, off switches and round buttons.
    static let well = Color(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.1))

    /// Hairlines between rows.
    static let hairline = Color(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.09))

    /// The edge of a field on the solid panel, where it would otherwise vanish into its group.
    static let fieldBorder = Color(light: NSColor(white: 0, alpha: 0.14), dark: NSColor(white: 1, alpha: 0.14))

    /// Validation messages. Darker than system red in light mode, so it reads as text.
    static let danger = Color(
        light: NSColor(srgbRed: 0.843, green: 0, blue: 0.082, alpha: 1),
        dark: NSColor(srgbRed: 1, green: 0.412, blue: 0.38, alpha: 1)
    )

    /// Accent-tinted backgrounds: the icon tile, the selected icon, the highlighted search result.
    static let accentSoft = Color.accentColor.opacity(0.18)

    /// Grouped boxes inside the popover.
    static func group(on background: PopoverBackground) -> Color {
        switch background {
        case .liquidGlass: Color(light: NSColor(white: 1, alpha: 0.55), dark: NSColor(white: 1, alpha: 0.08))
        case .solid: Color(light: .white, dark: NSColor(white: 1, alpha: 0.06))
        }
    }

    /// Text, date and time fields inside a group.
    static func field(on background: PopoverBackground) -> Color {
        switch background {
        case .liquidGlass: Color(light: NSColor(white: 1, alpha: 0.75), dark: NSColor(white: 1, alpha: 0.12))
        case .solid: Color(light: .white, dark: NSColor(white: 1, alpha: 0.1))
        }
    }

    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
}

/// Corner radii. They follow the system the app runs on, not the background: macOS 26 draws
/// capsule controls and a rounder popover whether it's glass or solid.
enum Radius {
    static let isTahoe: Bool = {
        if #available(macOS 26, *) { true } else { false }
    }()

    /// Grouped boxes: the popover's corner radius minus its padding, so the corners stay concentric.
    static let group: CGFloat = isTahoe ? 10 : 8
    /// Date, time and search fields: capsules on macOS 26.
    static let field: CGFloat = isTahoe ? 12 : 6
    /// Text fields.
    static let textField: CGFloat = isTahoe ? 8 : 6
    /// The icon picker's wells: circles on macOS 26.
    static let well: CGFloat = isTahoe ? 13 : 6
    /// The emoji picker's cells, circles on macOS 26 like the wells.
    static let emojiCell: CGFloat = isTahoe ? 14 : 7
    /// The countdown's icon beside its name.
    static let tile: CGFloat = isTahoe ? 8 : 7
}

extension EnvironmentValues {
    private struct PopoverBackgroundKey: EnvironmentKey {
        static let defaultValue = PopoverBackground.liquidGlass
    }

    /// The background the popover is actually drawn on, after `PopoverBackground.effective`.
    var popoverBackground: PopoverBackground {
        get { self[PopoverBackgroundKey.self] }
        set { self[PopoverBackgroundKey.self] = newValue }
    }
}

/// A box of rows on the popover, like a grouped form section.
struct GroupedBox<Content: View>: View {
    @Environment(\.popoverBackground) private var background
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.group(on: background), in: RoundedRectangle(cornerRadius: Radius.group, style: .continuous))
    }
}

/// A hairline between rows of a `GroupedBox`, starting `inset` from its leading edge.
struct RowDivider: View {
    var inset: CGFloat = 12

    var body: some View {
        Rectangle()
            .fill(Color.hairline)
            .frame(height: 1)
            .padding(.leading, inset)
    }
}

/// The small print under a group.
struct Footnote: View {
    let text: Text

    init(_ text: Text) {
        self.text = text
    }

    init(_ key: LocalizedStringKey) {
        text = Text(key)
    }

    var body: some View {
        text
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
    }
}

/// The background of a text, date, time or search field: a capsule on macOS 26, with an accent ring
/// while it's active and a red one when its value is wrong.
struct FieldBackground: ViewModifier {
    @Environment(\.popoverBackground) private var background
    var radius = Radius.field
    var isActive = false
    var isInvalid = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background(Color.field(on: background), in: shape)
            .overlay {
                if isInvalid {
                    shape.strokeBorder(Color.danger, lineWidth: 1.5)
                } else if isActive {
                    shape.strokeBorder(Color.accentColor, lineWidth: 2)
                } else if background == .solid {
                    shape.strokeBorder(Color.fieldBorder, lineWidth: 0.5)
                }
            }
    }
}

extension View {
    func fieldBackground(radius: CGFloat = Radius.field, isActive: Bool = false, isInvalid: Bool = false) -> some View {
        modifier(FieldBackground(radius: radius, isActive: isActive, isInvalid: isInvalid))
    }
}

/// The countdown's icon: an SF Symbol or an emoji.
struct CountdownIconView: View {
    let icon: CountdownIcon

    var body: some View {
        switch icon {
        case .symbol(let name): Image(systemName: name)
        case .emoji(let emoji): Text(emoji)
        }
    }
}

/// Type from the design's scale. Every number that changes uses tabular digits.
extension Font {
    /// Days left, the final-day clock, Today.
    static let count = Font.system(size: 60, weight: .semibold, design: .rounded)
    /// The unit beside the count.
    static let countUnit = Font.system(size: 20, weight: .medium, design: .rounded)
    /// Weeks, weekends, weekdays.
    static let stat = Font.system(size: 17, weight: .semibold, design: .rounded)
    /// Runway labels.
    static let micro = Font.caption.weight(.medium)
}
