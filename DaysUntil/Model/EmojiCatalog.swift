import CoreText
import Foundation

/// The emoji the icon picker offers: Unicode's list in the categories and order of Apple's emoji
/// picker, with CLDR's English names and keywords for search. It's read from `Emoji.tsv`, which
/// `scripts/make-emoji-list.py` builds, and keeps only the emoji this Mac can draw, so a list made
/// for a newer Unicode never shows empty boxes.
nonisolated enum EmojiCatalog {
    enum Category: String, CaseIterable, Sendable {
        case smileys, animals, food, activity, travel, objects, symbols, flags

        var title: String {
            switch self {
            case .smileys: String(localized: "Smileys & People")
            case .animals: String(localized: "Animals & Nature")
            case .food: String(localized: "Food & Drink")
            case .activity: String(localized: "Activity")
            case .travel: String(localized: "Travel & Places")
            case .objects: String(localized: "Objects")
            case .symbols: String(localized: "Symbols")
            case .flags: String(localized: "Flags")
            }
        }

        /// The category's button in the picker's bar, as in Apple's picker.
        var symbol: String {
            switch self {
            case .smileys: "face.smiling"
            case .animals: "pawprint"
            case .food: "fork.knife"
            case .activity: "soccerball"
            case .travel: "car"
            case .objects: "lightbulb"
            case .symbols: "heart"
            case .flags: "flag"
            }
        }
    }

    struct Emoji: Hashable, Sendable {
        let character: String
        /// CLDR's short name, e.g. "airplane" or "flag: Japan".
        let name: String
        /// CLDR's keywords not already in the name, e.g. "plane" and "travel" for ✈️.
        let keywords: [String]
        let category: Category
    }

    struct Section: Sendable {
        let category: Category
        let emoji: [Emoji]
    }

    static let all: [Emoji] = load(Bundle.main.url(forResource: "Emoji", withExtension: "tsv"))

    /// The catalog by category, in order, for the picker's sections.
    static let sections: [Section] = Category.allCases.map { category in
        Section(category: category, emoji: all.filter { $0.category == category })
    }

    /// The emoji whose name or keywords match every word of the query, best first: the name is the
    /// query, then each word is a word of the name, a keyword, the start of a word of the name, the
    /// start of a keyword. Among equals, single emoji come before sequences, so "plane" finds ✈️
    /// before 🧑‍✈️, and then the catalog's order holds.
    static func results(for query: String, in emoji: [Emoji] = all) -> [Emoji] {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let query = query.trimmingCharacters(in: .whitespaces)
        let queryWords = words(in: query)
        guard !queryWords.isEmpty else { return [] }
        func rank(_ emoji: Emoji) -> Int? {
            if emoji.name.compare(query, options: options) == .orderedSame { return 0 }
            let nameWords = words(in: emoji.name)
            let keywordWords = emoji.keywords.flatMap(words(in:))
            func equal(_ candidates: [Substring], _ word: Substring) -> Bool {
                candidates.contains { $0.compare(word, options: options) == .orderedSame }
            }
            func start(_ candidates: [Substring], _ word: Substring) -> Bool {
                candidates.contains { $0.range(of: word, options: options.union(.anchored)) != nil }
            }
            return queryWords.map { word in
                if equal(nameWords, word) { return 1 }
                if equal(keywordWords, word) { return 2 }
                if start(nameWords, word) { return 3 }
                if start(keywordWords, word) { return 4 }
                return Int.max
            }
            .max()
            .flatMap { $0 == Int.max ? nil : $0 }
        }
        return emoji.enumerated()
            .compactMap { index, emoji in
                rank(emoji).map { (emoji, $0, emoji.character.unicodeScalars.contains("\u{200D}") ? 1 : 0, index) }
            }
            .sorted { ($0.1, $0.2, $0.3) < ($1.1, $1.2, $1.3) }
            .map(\.0)
    }

    private static func words(in text: String) -> [Substring] {
        text.split { $0.isWhitespace || $0 == ":" || $0 == "-" || $0 == "," }
    }

    static func load(_ url: URL?) -> [Emoji] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let font = CTFontCreateWithName("AppleColorEmoji" as CFString, 20, nil)
        let width = lineWidth("😀", font: font)
        return text.split(separator: "\n").compactMap { line in
            guard !line.hasPrefix("#") else { return nil }
            let fields = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 4, let category = Category(rawValue: String(fields[0])) else { return nil }
            let character = String(fields[1])
            guard canDraw(character, font: font, width: width) else { return nil }
            return Emoji(
                character: character,
                name: String(fields[2]),
                keywords: fields[3].split(separator: "|").map(String.init),
                category: category
            )
        }
    }

    /// Whether Apple Color Emoji draws the emoji as one, which it doesn't for emoji newer than the
    /// Mac: those fall back to another font, or a sequence comes apart into several emoji.
    private static func canDraw(_ emoji: String, font: CTFont, width: Double) -> Bool {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: emoji, attributes: [fontAttribute: font]))
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        let allColorEmoji = runs.allSatisfy { run in
            let attributes = CTRunGetAttributes(run) as NSDictionary
            guard let runFont = attributes[kCTFontAttributeName] else { return false }
            return CTFontCopyPostScriptName(runFont as! CTFont) as String == "AppleColorEmoji"
        }
        return !runs.isEmpty && allColorEmoji && CTLineGetTypographicBounds(line, nil, nil, nil) < width * 1.5
    }

    private static let fontAttribute = NSAttributedString.Key(kCTFontAttributeName as String)

    private static func lineWidth(_ text: String, font: CTFont) -> Double {
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [fontAttribute: font]))
        return CTLineGetTypographicBounds(line, nil, nil, nil)
    }
}
