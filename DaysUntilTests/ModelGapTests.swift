import AppKit
import Testing
@testable import DaysUntil

struct NumberPhraseTests {
    @Test func splitsAtTheNumber() {
        let english = NumberPhrase("80 days", number: "80")
        #expect([english.before, english.number, english.after] == ["", "80", "days"])
        // A translation may put words first.
        let words = NumberPhrase("あと 3 日", number: "3")
        #expect([words.before, words.number, words.after] == ["あと", "3", "日"])
        let attached = NumberPhrase("3天", number: "3")
        #expect([attached.before, attached.number, attached.after] == ["", "3", "天"])
    }

    @Test func aPhraseWithoutTheNumberIsAllWords() {
        let phrase = NumberPhrase("a few days", number: "80")
        #expect([phrase.before, phrase.number, phrase.after] == ["", "80", "a few days"])
    }
}

struct EmojiCategoryTests {
    @Test func eachCategoryHasATitleAndASymbol() {
        let categories = EmojiCatalog.Category.allCases
        #expect(Set(categories.map(\.title)).count == categories.count)
        #expect(categories.map(\.title) == [
            "Smileys & People", "Animals & Nature", "Food & Drink", "Activity",
            "Travel & Places", "Objects", "Symbols", "Flags",
        ])
        for category in categories {
            #expect(NSImage(systemSymbolName: category.symbol, accessibilityDescription: nil) != nil, "\(category)")
        }
    }
}

@MainActor
struct DraftGapTests {
    let tokyo = Place(timeZoneID: "Asia/Tokyo", name: "Tokyo")
    let zone = TimeZone(identifier: "America/Los_Angeles")!

    @Test func aNewCountdownAfterTheDayKeepsTheNameIconAndPlace() throws {
        let reached = Countdown(name: "Trip", icon: .emoji("🧳"), targetDate: Date().addingTimeInterval(-86_400 * 3),
                                showsTime: true, place: tokyo, startDate: Date().addingTimeInterval(-86_400 * 60))
        let now = Date()
        let draft = Draft(after: reached, now: now, timeZone: zone)
        #expect(draft.name == "Trip")
        #expect(draft.icon == .emoji("🧳"))
        #expect(draft.hasPlace)
        #expect(draft.place == tokyo)
        // Dated afresh, as a new countdown is: a month out, counting from today.
        let fresh = Draft(now: now, timeZone: zone)
        #expect(draft.dateInput == fresh.dateInput)
        #expect(draft.startInput == fresh.startInput)
        #expect(draft.countdown?.targetDate == fresh.targetDate)
    }

    @Test func aPlaceSavedWithoutANameGetsItsCity() throws {
        var draft = Draft(now: Date(), timeZone: zone)
        draft.name = "Trip"
        draft.hasPlace = true
        draft.place = Place(timeZoneID: "Asia/Tokyo", name: "  ")
        let countdown = try #require(draft.countdown)
        #expect(countdown.place?.name == PlaceSearch.city(of: "Asia/Tokyo"))
    }

    @Test func noCountdownWithoutAValidDay() {
        var draft = Draft(now: Date(), timeZone: zone)
        draft.name = "Trip"
        draft.dateInput.text = "not a date"
        #expect(draft.candidates.isEmpty)
        #expect(draft.countdown == nil)
        draft.dateInput.cancelTyping()
        draft.startInput.text = "nor this"
        #expect(draft.startDate == nil)
        #expect(draft.countdown == nil)
    }
}

struct ModelEdgeTests {
    @Test func aCountdownFromANewerVersionIsRejected() {
        let json = #"{"version": 3, "name": "Trip", "icon": {"symbol": "house"}}"#
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Countdown.self, from: Data(json.utf8))
        }
    }

    @Test func iconsSayWhetherTheyreEmoji() {
        #expect(CountdownIcon.emoji("🎄").emoji == "🎄")
        #expect(CountdownIcon.symbol("house").emoji == nil)
    }

    @Test func committingTypedTextSelectsItsDay() {
        var entry = DateEntry(CalendarDay(year: 2027, month: 3, day: 10))
        entry.text = "2027-12-19"
        let committed = entry.commit()
        #expect(committed)
        #expect(entry.selected == CalendarDay(year: 2027, month: 12, day: 19))
        #expect(entry.text == nil)
        entry.text = "2027-02-30"
        let impossible = entry.commit()
        #expect(!impossible)
        #expect(entry.selected == CalendarDay(year: 2027, month: 12, day: 19))
        #expect(DateEntry.parse("2027-1-1-1") == nil)
    }

    @Test func untilTodayOnTheDayItself() {
        let calendar = CountdownMath.gregorian(in: TimeZone(identifier: "America/Los_Angeles")!)
        let moment = calendar.date(from: DateComponents(year: 2026, month: 12, day: 18, hour: 21, minute: 40))!
        let text = CountdownMath.untilText(moment: moment, now: moment - 3_600, calendar: calendar)
        #expect(text.hasPrefix("Until "))
        #expect(text.hasSuffix(" today"))
    }

    @Test func halfHourOffsetsReadInMinutes() {
        let kolkata = TimeZone(identifier: "Asia/Kolkata")!
        let dhaka = TimeZone(identifier: "Asia/Dhaka")!
        #expect(CountdownMath.offsetText(of: kolkata, from: dhaka, at: Date()) == "30m behind")
        #expect(CountdownMath.offsetText(of: dhaka, from: kolkata, at: Date()) == "30m ahead")
    }

    @Test @MainActor func turningOffWhatIsntOnDoesNothing() {
        let service = LoginServiceStub()
        let login = LaunchAtLogin(service: service)
        login.set(false)
        #expect(service.unregisterCalls == 0)
        #expect(login.failedRequest == nil)
    }
}

@Suite @MainActor
struct PopoverStateTests {
    let defaults: UserDefaults = MemoryDefaults()
    let countdown = Countdown(name: "Trip", icon: .symbol("airplane"), targetDate: Date().addingTimeInterval(86_400 * 30),
                              showsTime: false, place: Place(timeZoneID: "Asia/Tokyo", name: "Tokyo"), startDate: Date())

    private func state(with countdown: Countdown?) -> (CountdownStore, PopoverState) {
        let store = CountdownStore(defaults: defaults)
        store.countdown = countdown
        return (store, PopoverState(store: store, launchAtLogin: LaunchAtLogin(service: LoginServiceStub())))
    }

    @Test func editOpensTheFormOnTheCountdown() {
        let (_, state) = state(with: countdown)
        #expect(!state.isEditing)
        state.confirmDelete()
        state.edit()
        #expect(state.isEditing)
        #expect(!state.isConfirmingDelete)
        #expect(state.draft.countdown?.targetDate == countdown.targetDate)
        state.cancel()
        #expect(!state.isEditing)
    }

    @Test func withoutACountdownThereIsNothingToEdit() {
        let (_, state) = state(with: nil)
        #expect(state.isEditing)
        state.cancel()
        state.edit()
        state.startOver()
        state.confirmDelete()
        #expect(!state.isEditing)
        #expect(!state.isConfirmingDelete)
    }

    @Test func startingOverKeepsTheNameIconAndPlace() {
        let (store, state) = state(with: countdown)
        state.startOver()
        #expect(state.isEditing)
        #expect(state.draft.name == "Trip")
        #expect(state.draft.icon == .symbol("airplane"))
        #expect(state.draft.place == countdown.place)
        // The countdown stays until a new one is saved.
        #expect(store.countdown == countdown)
    }

    @Test func eachOpeningIsNoted() throws {
        let (_, state) = state(with: countdown)
        #expect(state.openedAt == nil)
        state.isShown = true
        let first = try #require(state.openedAt)
        state.isShown = true
        #expect(state.openedAt == first)
        state.isShown = false
        state.isShown = true
        #expect(try #require(state.openedAt) >= first)
    }
}
