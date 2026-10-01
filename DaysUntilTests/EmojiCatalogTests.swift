import Foundation
import Testing
@testable import DaysUntil

struct EmojiCatalogTests {
    @Test func loadsEveryCategoryInApplesOrder() {
        #expect(EmojiCatalog.all.count > 1_800)
        #expect(EmojiCatalog.sections.map(\.category) == EmojiCatalog.Category.allCases)
        #expect(EmojiCatalog.sections.allSatisfy { !$0.emoji.isEmpty })
        #expect(EmojiCatalog.all.first?.character == "😀")
        // Activity comes before Travel & Places, as in Apple's picker, though Unicode has it after.
        let categories = EmojiCatalog.all.map(\.category)
        #expect(categories.lastIndex(of: .activity)! < categories.firstIndex(of: .travel)!)
    }

    @Test func leavesOutSkinTonesAndComponents() {
        let skinTones = Set((0x1F3FB...0x1F3FF).compactMap(Unicode.Scalar.init))
        #expect(!EmojiCatalog.all.contains { $0.character.unicodeScalars.contains(where: skinTones.contains) })
        #expect(!EmojiCatalog.all.contains { $0.name.hasPrefix("regional indicator") || $0.name == "red hair" })
    }

    @Test func findsByNameThenKeyword() {
        #expect(EmojiCatalog.results(for: "ring").first?.character == "💍")
        #expect(EmojiCatalog.results(for: "Christmas").first?.character == "🎄")
        #expect(EmojiCatalog.results(for: "christmas tree").first?.character == "🎄")
        // ✈️ and the pilots all have the keyword "plane"; the single emoji comes first.
        #expect(EmojiCatalog.results(for: "plane").first?.character == "✈️")
        // A keyword: in the first row, among others with "home".
        #expect(EmojiCatalog.results(for: "home").prefix(9).map(\.character).contains("🏠"))
        #expect(EmojiCatalog.results(for: "japan").map(\.character).contains("🇯🇵"))
        #expect(EmojiCatalog.results(for: "  ").isEmpty)
        #expect(EmojiCatalog.results(for: "zzzz").isEmpty)
    }

    @Test func dropsWhatTheMacCantDraw() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("EmojiCatalogTests.tsv")
        // A real emoji, a sequence of two that has no emoji of its own, and plain text.
        try "# header\ntravel\t✈️\tairplane\tplane|travel\nsmileys\t🏠✈️\ttwo\t\nsymbols\tA\tletter\t\n"
            .write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let loaded = EmojiCatalog.load(url)
        #expect(loaded.map(\.character) == ["✈️"])
        #expect(loaded.first?.keywords == ["plane", "travel"])
    }
}
