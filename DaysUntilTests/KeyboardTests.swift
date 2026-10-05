import AppKit
import Combine
import SwiftUI
import Testing
@testable import DaysUntil

// The form's keyboard, driven with real key events through the views' own key monitors, in windows
// off screen. Keys that only beep are left out, since a beep would sound on the Mac running the tests.

private enum Field: Hashable {
    case field
}

// MARK: - Emoji picker

/// The emoji picker with its search field focused, as the form opens it.
private struct EmojiPickerHost: View {
    let selection: String?
    var focuses = true
    let picked: Calls<String>
    let closed: Calls<Void>
    @FocusState private var focus: Field?

    var body: some View {
        EmojiPicker(selection: selection, focus: $focus, searchField: .field, pick: picked.record, close: { closed.record(()) })
            .onAppear { if focuses { focus = .field } }
    }
}

@Suite @MainActor
struct EmojiPickerKeyboardTests {
    let picked = Calls<String>()
    let closed = Calls<Void>()
    /// The picker's rows: nine to a row, each category starting a new one.
    let rows = EmojiCatalog.sections.flatMap { section in
        stride(from: 0, to: section.emoji.count, by: 9).map { Array(section.emoji[$0..<min($0 + 9, section.emoji.count)]).map(\.character) }
    }

    private func host(selection: String? = nil, focuses: Bool = true) -> OffscreenHost {
        OffscreenHost(EmojiPickerHost(selection: selection, focuses: focuses, picked: picked, closed: closed))
    }

    @Test func arrowsMoveThroughTheRowsAndReturnPicks() {
        let host = host()
        defer { host.close() }
        // The first key starts on the first emoji.
        host.press(OffscreenHost.down)
        host.press(OffscreenHost.returnKey)
        host.press(OffscreenHost.right)
        host.press(OffscreenHost.returnKey)
        // Down keeps the column.
        host.press(OffscreenHost.down)
        host.press(OffscreenHost.returnKey)
        host.press(OffscreenHost.up)
        host.press(OffscreenHost.left)
        host.press(OffscreenHost.returnKey)
        #expect(picked.values == [rows[0][0], rows[0][1], rows[1][1], rows[0][0]])
        #expect(closed.values.isEmpty)
    }

    @Test func aRowStartsEachCategory() {
        let host = host()
        defer { host.close() }
        // From the last row of the first category, down goes to the first row of the next.
        let lastSmiley = (EmojiCatalog.sections[0].emoji.count - 1) / 9
        host.press(OffscreenHost.down)
        for _ in 0..<lastSmiley {
            host.press(OffscreenHost.down)
        }
        host.press(OffscreenHost.returnKey)
        #expect(picked.values == [rows[lastSmiley][0]])
        host.press(OffscreenHost.down)
        host.press(OffscreenHost.returnKey)
        #expect(picked.values.last == EmojiCatalog.sections[1].emoji[0].character)
    }

    @Test func startsOnTheCountdownsOwnEmoji() {
        let selection = EmojiCatalog.all[40].character
        let host = host(selection: selection)
        defer { host.close() }
        host.press(OffscreenHost.up)
        host.press(OffscreenHost.returnKey)
        #expect(picked.values == [selection])
    }

    @Test func typingSearchesAndReturnPicksTheFirstResult() throws {
        let host = host()
        defer { host.close() }
        host.type("house")
        let results = EmojiCatalog.results(for: "house").map(\.character)
        try #require(results.count > 2)
        host.press(OffscreenHost.returnKey)
        host.press(OffscreenHost.right)
        host.press(OffscreenHost.returnKey)
        #expect(picked.values == [results[0], results[1]])
    }

    @Test func escapeClearsTheSearchThenCloses() {
        let host = host()
        defer { host.close() }
        host.type("zzzzzzqqqq")
        #expect(EmojiCatalog.results(for: "zzzzzzqqqq").isEmpty)
        host.press(OffscreenHost.escape)
        #expect(closed.values.isEmpty)
        #expect(host.editor?.string == "")
        host.press(OffscreenHost.escape)
        #expect(closed.values.count == 1)
    }

    @Test func keysNeedTheSearchField() {
        let host = host(focuses: false)
        defer { host.close() }
        host.press(OffscreenHost.down)
        host.press(OffscreenHost.escape)
        #expect(picked.values.isEmpty)
        #expect(closed.values.isEmpty)
    }
}

// MARK: - Calendar

@MainActor
final class CalendarModel: ObservableObject {
    @Published var entry: DateEntry
    @Published var isOpen = true

    init(_ day: CalendarDay) {
        entry = DateEntry(day)
    }
}

private struct CalendarHost: View {
    @ObservedObject var model: CalendarModel
    var focuses = true
    var isEnabled: (Date) -> Bool = { _ in true }
    @FocusState private var focus: Field?

    var body: some View {
        CalendarField(
            title: "Date", entry: $model.entry, isOpen: $model.isOpen, focus: $focus, field: .field,
            timeZone: .current, isEnabled: isEnabled, caption: { Text($0.formatted()) }, error: nil
        )
        .onAppear { if focuses { focus = .field } }
    }
}

@Suite @MainActor
struct CalendarKeyboardTests {
    let model = CalendarModel(CalendarDay(year: 2027, month: 3, day: 10))

    private func host(focuses: Bool = true) -> OffscreenHost {
        OffscreenHost(CalendarHost(model: model, focuses: focuses))
    }

    @Test func arrowsMoveByDayAndWeekPageKeysByMonth() {
        let host = host()
        defer { host.close() }
        var days: [CalendarDay] = []
        for key in [OffscreenHost.right, OffscreenHost.left, OffscreenHost.down, OffscreenHost.up, OffscreenHost.pageDown, OffscreenHost.pageUp] {
            host.press(key)
            days.append(model.entry.selected)
        }
        #expect(days.map { "\($0.month)/\($0.day)" } == ["3/11", "3/10", "3/17", "3/10", "4/10", "3/10"])
        #expect(model.isOpen)
    }

    @Test func returnPicksAndCloses() {
        let host = host()
        defer { host.close() }
        host.press(OffscreenHost.down)
        host.press(OffscreenHost.returnKey)
        #expect(!model.isOpen)
        #expect(model.entry.selected == CalendarDay(year: 2027, month: 3, day: 17))
    }

    @Test func tJumpsToToday() {
        let host = host()
        defer { host.close() }
        host.press(OffscreenHost.t, "t")
        #expect(model.entry.selected == CountdownMath.calendarDay(of: Date(), in: .current))
    }

    @Test func typedDatesTakeTheArrowsAndReturnCommitsThem() {
        let host = host()
        defer { host.close() }
        host.type("2027-12-19")
        #expect(model.entry.text == "2027-12-19")
        // Once something's typed, the arrows edit the text.
        host.press(OffscreenHost.left)
        #expect(model.entry.selected == CalendarDay(year: 2027, month: 3, day: 10))
        host.press(OffscreenHost.returnKey)
        #expect(model.entry.selected == CalendarDay(year: 2027, month: 12, day: 19))
        #expect(model.entry.text == nil)
        #expect(!model.isOpen)
    }

    @Test func escapeDropsTheTypingAndCloses() {
        let host = host()
        defer { host.close() }
        host.type("not a date")
        #expect(!model.entry.isValid)
        host.press(OffscreenHost.escape)
        #expect(model.entry.text == nil)
        #expect(model.entry.selected == CalendarDay(year: 2027, month: 3, day: 10))
        #expect(!model.isOpen)
    }

    @Test func typingOpensTheCalendarAndClosingCommits() {
        model.isOpen = false
        let host = host()
        defer { host.close() }
        host.type("2028-01-02")
        #expect(model.isOpen)
        model.isOpen = false
        host.settle()
        #expect(model.entry.selected == CalendarDay(year: 2028, month: 1, day: 2))
        #expect(model.entry.text == nil)
    }

    @Test func keysNeedTheField() {
        let host = host(focuses: false)
        defer { host.close() }
        host.press(OffscreenHost.right)
        host.press(OffscreenHost.escape)
        #expect(model.entry.selected == CalendarDay(year: 2027, month: 3, day: 10))
        #expect(model.isOpen)
    }
}

// MARK: - Place

@MainActor
final class PlaceModel: ObservableObject {
    @Published var place: Place?
}

private struct PlaceHost: View {
    @ObservedObject var model: PlaceModel
    var moment: Date?
    var focuses = true
    @FocusState private var focus: Field?

    var body: some View {
        PlaceField(place: $model.place, moment: moment, now: Date(), focus: $focus, searchField: .field)
            .onAppear { if focuses { focus = .field } }
    }
}

@Suite @MainActor
struct PlaceKeyboardTests {
    let model = PlaceModel()

    private func host(focuses: Bool = true) -> OffscreenHost {
        OffscreenHost(PlaceHost(model: model, moment: Date().addingTimeInterval(86_400 * 30), focuses: focuses))
    }

    private func place(_ zone: PlaceSearch.Zone) -> Place {
        Place(timeZoneID: zone.identifier, name: zone.city)
    }

    @Test func typingSearchesAndReturnPicksTheHighlightedResult() throws {
        let host = host()
        defer { host.close() }
        host.type("Tokyo")
        let first = try #require(PlaceSearch.results(for: "Tokyo").first)
        host.press(OffscreenHost.returnKey)
        #expect(model.place == place(first))
        // Picking leaves the field, which then shows the place.
        #expect(host.editor == nil)
    }

    @Test func arrowsMoveThroughTheResults() throws {
        let host = host()
        defer { host.close() }
        host.type("America")
        let results = PlaceSearch.results(for: "America")
        try #require(results.count > 2)
        host.press(OffscreenHost.up)
        host.press(OffscreenHost.down)
        host.press(OffscreenHost.down)
        host.press(OffscreenHost.up)
        host.press(OffscreenHost.returnKey)
        #expect(model.place == place(results[1]))
    }

    @Test func escapeClearsTheSearch() {
        let host = host()
        defer { host.close() }
        host.type("Lond")
        host.press(OffscreenHost.escape)
        #expect(host.editor?.string == "")
        #expect(model.place == nil)
    }

    @Test func escapeLeavesAPickedPlaceAsItWas() throws {
        let tokyo = place(try #require(PlaceSearch.results(for: "Tokyo").first))
        model.place = tokyo
        let host = host()
        defer { host.close() }
        // The search starts from the place's name.
        #expect(host.editor?.string == tokyo.name)
        host.type("Par")
        host.press(OffscreenHost.escape)
        #expect(host.editor == nil)
        #expect(model.place == tokyo)
    }

    @Test func anInputMethodKeepsReturnWhileComposing() throws {
        let host = host()
        defer { host.close() }
        let editor = try #require(host.editor)
        editor.setMarkedText("Tok", selectedRange: NSRange(location: 3, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        host.settle()
        host.press(OffscreenHost.returnKey)
        #expect(model.place == nil)
    }

    @Test func keysNeedTheField() {
        let host = host(focuses: false)
        defer { host.close() }
        host.press(OffscreenHost.down)
        host.press(OffscreenHost.returnKey)
        #expect(model.place == nil)
    }
}
