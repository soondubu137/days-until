import SwiftUI

/// The emoji well's picker, inside the group under the icon wells: a search, every emoji in the
/// categories of Apple's picker, and a bar that jumps to each. The system's emoji picker
/// can't be used from the popover; see docs/DESIGN.md, "Edit form".
///
/// Keyboard: typing searches names and keywords, the arrow keys move through the emoji, Return
/// picks, and Esc clears the search, then closes.
struct EmojiPicker<Focus: Hashable>: View {
    /// The countdown's emoji, if its icon is one.
    let selection: String?
    var focus: FocusState<Focus?>.Binding
    let searchField: Focus
    let pick: (String) -> Void
    let close: () -> Void

    @State private var query = ""
    /// The emoji the keyboard is on.
    @State private var highlighted: String?

    private let columnCount = 9

    var body: some View {
        let results = EmojiCatalog.results(for: query)
        ScrollViewReader { proxy in
            VStack(spacing: 8) {
                searchBox
                ScrollView {
                    if query.isEmpty {
                        sections
                    } else if results.isEmpty {
                        Text("No Emoji Found")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 190)
                    } else {
                        grid(results)
                    }
                }
                .frame(height: 198)
                if query.isEmpty {
                    categoryBar(proxy)
                }
            }
            .onChange(of: query) { query in
                highlighted = EmojiCatalog.results(for: query).first?.character
                if let first = query.isEmpty ? EmojiCatalog.all.first?.character : highlighted {
                    proxy.scrollTo(first, anchor: .top)
                }
            }
            .onChange(of: highlighted) { highlighted in
                if let highlighted {
                    proxy.scrollTo(highlighted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .onKeyDown { handleKey($0, results: results) }
    }

    private var searchBox: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Search Emoji", text: $query, prompt: Text("Search emoji"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .focused(focus, equals: searchField)
        }
        .padding(.horizontal, 10)
        .frame(height: 24)
        .fieldBackground(isActive: focus.wrappedValue == searchField)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 0), count: columnCount)
    }

    private var sections: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 2) {
            ForEach(EmojiCatalog.sections, id: \.category) { section in
                Section {
                    cells(section.emoji)
                } header: {
                    Text(section.category.title)
                        .font(.micro)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                        .id(section.category)
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
    }

    private func grid(_ emoji: [EmojiCatalog.Emoji]) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            cells(emoji)
        }
    }

    private func cells(_ emoji: [EmojiCatalog.Emoji]) -> some View {
        ForEach(emoji, id: \.character) { emoji in
            EmojiCell(
                emoji: emoji,
                isSelected: emoji.character == selection,
                isHighlighted: emoji.character == highlighted,
                pick: pick
            )
            .id(emoji.character)
        }
    }

    private func categoryBar(_ proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            ForEach(EmojiCatalog.Category.allCases, id: \.self) { category in
                Button {
                    proxy.scrollTo(category, anchor: .top)
                } label: {
                    Image(systemName: category.symbol)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .frame(maxWidth: .infinity)
                .help(category.title)
                .accessibilityLabel(Text(category.title))
            }
        }
    }

    // MARK: - Keyboard

    private func handleKey(_ event: NSEvent, results: [EmojiCatalog.Emoji]) -> Bool {
        guard focus.wrappedValue == searchField else { return false }
        let shown = query.isEmpty ? EmojiCatalog.all : results
        switch event.key {
        case .left where highlighted != nil: step(by: -1, in: shown)
        case .right where highlighted != nil: step(by: 1, in: shown)
        case .up: moveRow(by: -1, in: shown)
        case .down: moveRow(by: 1, in: shown)
        case .returnKey:
            if let highlighted {
                pick(highlighted)
            } else {
                NSSound.beep()
            }
        case .escape:
            if query.isEmpty {
                close()
            } else {
                query = ""
            }
        default:
            return false
        }
        return true
    }

    /// Where the keyboard starts: the countdown's emoji when it's on show, or the first one.
    private func start(in shown: [EmojiCatalog.Emoji]) -> String? {
        shown.first { $0.character == selection }?.character ?? shown.first?.character
    }

    private func step(by amount: Int, in shown: [EmojiCatalog.Emoji]) {
        guard let index = shown.firstIndex(where: { $0.character == highlighted }) else {
            highlighted = start(in: shown)
            return
        }
        let moved = index + amount
        if shown.indices.contains(moved) {
            highlighted = shown[moved].character
        } else {
            NSSound.beep()
        }
    }

    /// Up or down a row on screen, keeping the column. Each section starts a new row, so the rows
    /// come from the sections when they're on show.
    private func moveRow(by amount: Int, in shown: [EmojiCatalog.Emoji]) {
        let groups = query.isEmpty ? EmojiCatalog.sections.map(\.emoji) : [shown]
        let rows = groups.flatMap { emoji in
            stride(from: 0, to: emoji.count, by: columnCount).map { Array(emoji[$0..<min($0 + columnCount, emoji.count)]) }
        }
        guard let row = rows.firstIndex(where: { $0.contains { $0.character == highlighted } }),
              let column = rows[row].firstIndex(where: { $0.character == highlighted })
        else {
            highlighted = start(in: shown)
            return
        }
        guard rows.indices.contains(row + amount) else {
            NSSound.beep()
            return
        }
        let target = rows[row + amount]
        highlighted = target[min(column, target.count - 1)].character
    }
}

private struct EmojiCell: View {
    let emoji: EmojiCatalog.Emoji
    let isSelected: Bool
    let isHighlighted: Bool
    let pick: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.emojiCell, style: .continuous)
        Button {
            pick(emoji.character)
        } label: {
            // Nine to a row fit beside a scroll bar that's always shown, as it is with a mouse.
            Text(emoji.character)
                .font(.system(size: 19))
                .frame(width: 28, height: 28)
                .background(background, in: shape)
                .overlay {
                    if isSelected {
                        shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
        .help(emoji.name)
        .accessibilityLabel(Text(emoji.name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected || isHighlighted { return .accentSoft }
        return isHovered ? .well : .clear
    }
}
