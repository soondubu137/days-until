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

    @Test func aCityNamedByDefaultFollowsTheLanguage() {
        let japanese = Locale(identifier: "ja_JP")
        #expect(PlaceSearch.localized(Place(timeZoneID: "Asia/Shanghai", name: "Shanghai"), locale: japanese).name == "上海")
        #expect(PlaceSearch.localized(Place(timeZoneID: "Asia/Shanghai", name: "상하이"), locale: Locale(identifier: "en")).name == "Shanghai")
        #expect(PlaceSearch.localized(Place(timeZoneID: "Asia/Shanghai", name: "Home"), locale: japanese).name == "Home")
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
        let december = try! Date("2026-12-18T17:00:00Z", strategy: .iso8601)
        #expect(PlaceSearch.utcOffset(of: TimeZone(identifier: "America/Los_Angeles")!, at: december) == "UTC−8")
        #expect(PlaceSearch.utcOffset(of: TimeZone(identifier: "UTC")!, at: september) == "UTC")
    }

    @Test @MainActor func targetPreviewShowsEachZonesDateAndYear() throws {
        let moment = try Date("2027-01-01T07:30:00Z", strategy: .iso8601)
        let locale = Locale(identifier: "en_US")
        let local = TimeZonePreview.formattedMoment(moment, in: TimeZone(identifier: "America/Los_Angeles")!, locale: locale)
        let there = TimeZonePreview.formattedMoment(moment, in: TimeZone(identifier: "Asia/Tokyo")!, locale: locale)
        #expect(local.contains("Dec 31, 2026"))
        #expect(local.contains("11:30"))
        #expect(there.contains("Jan 1, 2027"))
        #expect(there.contains("4:30"))
        // Conversion uses the target's daylight-saving offset, not the offset when editing.
        let summer = try Date("2027-07-01T07:30:00Z", strategy: .iso8601)
        let summerLocal = TimeZonePreview.formattedMoment(summer, in: TimeZone(identifier: "America/Los_Angeles")!, locale: locale)
        #expect(summerLocal.contains("Jul 1, 2027"))
        #expect(summerLocal.contains("12:30"))
    }
}
