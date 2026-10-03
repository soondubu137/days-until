import Foundation
import Testing
@testable import DaysUntil

struct PlaceSearchTests {
    @Test func cityComesFromTheIdentifier() {
        #expect(PlaceSearch.city(of: "Asia/Tokyo") == "Tokyo")
        #expect(PlaceSearch.city(of: "America/Argentina/Buenos_Aires") == "Buenos Aires")
    }

    @Test func cityIsTheSystemsNameInOtherLanguages() {
        #expect(PlaceSearch.city(of: "Asia/Tokyo", locale: Locale(identifier: "ja_JP")) == "東京")
        #expect(PlaceSearch.city(of: "America/New_York", locale: Locale(identifier: "zh_TW")) == "紐約")
        #expect(PlaceSearch.city(of: "America/Sao_Paulo", locale: Locale(identifier: "ko_KR")) == "상파울루")
        // The system names an alias for the zone it stands for, Toronto here, so it keeps its own name.
        #expect(PlaceSearch.city(of: "America/Montreal", locale: Locale(identifier: "zh_CN")) == "Montreal")
        #expect(PlaceSearch.city(of: "America/Sao_Paulo", locale: Locale(identifier: "en_JP")) == "Sao Paulo")
    }

    @Test func citiesStartingWithTheQueryComeFirst() {
        #expect(PlaceSearch.results(for: "tokyo").first?.identifier == "Asia/Tokyo")
        let new = PlaceSearch.results(for: "new")
        #expect(new.map(\.city).contains("New York"))
        // Zone-name matches such as New Zealand time only fill the slots left after those.
        let startsWithQuery = new.map { $0.city.hasPrefix("New") }
        #expect(startsWithQuery == startsWithQuery.sorted { $0 && !$1 })
        #expect(PlaceSearch.results(for: "york").map(\.identifier).contains("America/New_York"))
    }

    @Test func emptyQueryFindsNothing() {
        #expect(PlaceSearch.results(for: "  ").isEmpty)
    }

    @Test func utcOffsets() {
        let september = try! Date("2026-09-29T17:41:00Z", strategy: .iso8601)
        #expect(PlaceSearch.utcOffset(of: TimeZone(identifier: "Asia/Kolkata")!, at: september) == "UTC+5:30")
        #expect(PlaceSearch.utcOffset(of: TimeZone(identifier: "America/Los_Angeles")!, at: september) == "UTC−7")
        #expect(PlaceSearch.utcOffset(of: TimeZone(identifier: "UTC")!, at: september) == "UTC")
    }
}
