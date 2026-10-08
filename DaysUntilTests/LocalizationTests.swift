import Foundation
import Testing
@testable import DaysUntil

/// The translations: one for every string, in every language, with the same arguments as the
/// English, and read back the way the app reads them.
struct LocalizationTests {
    static let languages = ["ja", "ko", "zh-Hans", "zh-Hant"]

    /// The catalog's strings, read from the source, which keeps the translations' states.
    private static var strings: [String: [String: Any]] {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("DaysUntil/Localizable.xcstrings")
        let data = (try? Data(contentsOf: url)) ?? Data()
        let catalog = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return catalog?["strings"] as? [String: [String: Any]] ?? [:]
    }

    @Test func testsRunInEnglish() {
        // Other tests compare English text. The scheme's test language is English.
        #expect(Bundle.main.preferredLocalizations.first == "en")
    }

    @Test func everyStringIsTranslated() {
        let strings = Self.strings
        #expect(strings.count > 100)
        for (key, entry) in strings {
            #expect(entry["extractionState"] as? String != "stale", "\(key) is no longer used")
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            for language in Self.languages {
                let units = Self.units(in: localizations[language])
                #expect(!units.isEmpty, "\(key) has no \(language) translation")
                for unit in units {
                    #expect(unit["state"] as? String == "translated", "\(language): \(key)")
                    // A translation that takes other arguments would show the wrong values or crash.
                    let value = unit["value"] as? String ?? ""
                    #expect(Self.arguments(value) == Self.arguments(key), "\(language): \(key) → \(value)")
                }
            }
        }
    }

    @Test func englishCountsAgree() {
        #expect(String(localized: "\(1) days") == "1 day")
        #expect(String(localized: "\(2) days") == "2 days")
        #expect(String(localized: "\(1) weekends") == "1 weekend")
        #expect(String(localized: "\(1) days from \("Mon, Aug 3")") == "1 day from Mon, Aug 3")
        #expect(String(localized: "\(137) days from \("Mon, Aug 3")") == "137 days from Mon, Aug 3")
        #expect(String(localized: "\("Friday, December 18") · \(1) days before") == "Friday, December 18 · 1 day before")
        #expect(String(localized: "\("Friday, December 18") · \(3) days before") == "Friday, December 18 · 3 days before")
    }

    @Test func otherLanguagesReadTheirOwn() throws {
        let ja = try #require(Self.bundle("ja"))
        #expect(String(localized: "\(81)d", bundle: ja) == "81日")
        #expect(String(localized: "\(6)d \(14)h", bundle: ja) == "6日 14時間")
        #expect(String(localized: "\(137) days from \("8月3日(月)")", bundle: ja) == "8月3日(月)から137日")
        #expect(String(localized: "\(30) days to go · \("12月18日 金曜日")", bundle: ja) == "あと30日 · 12月18日 金曜日")
        let zh = try #require(Self.bundle("zh-Hans"))
        #expect(String(localized: "\(81)d", bundle: zh) == "81天")
        let zhHant = try #require(Self.bundle("zh-Hant"))
        #expect(String(localized: "\(5)h \(30)m", bundle: zhHant) == "5小時30分鐘")
        let ko = try #require(Self.bundle("ko"))
        #expect(String(localized: "\(6)d \(14)h", bundle: ko) == "6일 14시간")
        #expect(String(localized: "\("12월 18일 (금)") · \(3) days before", bundle: ko) == "12월 18일 (금) · 3일 전")
    }

    private static func bundle(_ language: String) -> Bundle? {
        Bundle.main.url(forResource: language, withExtension: "lproj").flatMap(Bundle.init(url:))
    }

    /// The string units in a localization, a plain one or one for each plural form.
    private static func units(in localization: Any?) -> [[String: Any]] {
        guard let localization = localization as? [String: Any] else { return [] }
        if let unit = localization["stringUnit"] as? [String: Any] { return [unit] }
        let plural = (localization["variations"] as? [String: Any])?["plural"] as? [String: Any] ?? [:]
        return plural.values.compactMap { ($0 as? [String: Any])?["stringUnit"] as? [String: Any] }
    }

    /// The format's arguments in the order they're passed: `%2$@ … %1$lld` is `["lld", "@"]`.
    private static func arguments(_ format: String) -> [String] {
        let pattern = /%(?:(\d+)\$)?(lld|@|%)/
        var next = 0
        var arguments: [Int: String] = [:]
        for match in format.matches(of: pattern) where match.2 != "%" {
            let position = match.1.flatMap { Int($0) } ?? next + 1
            next = position
            arguments[position] = String(match.2)
        }
        return arguments.keys.sorted().compactMap { arguments[$0] }
    }
}
