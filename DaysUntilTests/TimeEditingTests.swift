import Foundation
import Testing
@testable import DaysUntil

private let laZone = TimeZone(identifier: "America/Los_Angeles")!
private let londonZone = TimeZone(identifier: "Europe/London")!
private let tokyoZone = TimeZone(identifier: "Asia/Tokyo")!
private func instant(_ value: String) -> Date { try! Date(value, strategy: .iso8601) }

struct StrictTimeResolutionTests {
    @Test func fallBackHasTwoDistinctInstants() {
        let candidates = CountdownMath.possibleMoments(on: CalendarDay(year: 2026, month: 11, day: 1),
                                                       at: TimeOfDay(hour: 1, minute: 30), in: laZone)
        #expect(candidates == [instant("2026-11-01T08:30:00Z"), instant("2026-11-01T09:30:00Z")])
    }

    @Test func nonHourDSTChangesAreHandled() {
        let zone = TimeZone(identifier: "Australia/Lord_Howe")!
        let repeated = CountdownMath.possibleMoments(on: CalendarDay(year: 2027, month: 4, day: 4),
                                                     at: TimeOfDay(hour: 1, minute: 45), in: zone)
        #expect(repeated == [instant("2027-04-03T14:45:00Z"), instant("2027-04-03T15:15:00Z")])
        #expect(CountdownMath.possibleMoments(on: CalendarDay(year: 2026, month: 10, day: 4),
                at: TimeOfDay(hour: 2, minute: 15), in: zone).isEmpty)
    }

    @Test func invalidDatesAndSkippedCivilDaysAreRejected() {
        #expect(CountdownMath.validStartOfDay(CalendarDay(year: 2027, month: 2, day: 29), in: laZone) == nil)
        #expect(CountdownMath.validStartOfDay(CalendarDay(year: 2028, month: 2, day: 29), in: laZone) != nil)
        #expect(CountdownMath.validStartOfDay(CalendarDay(year: 2011, month: 12, day: 30), in: TimeZone(identifier: "Pacific/Apia")!) == nil)
        #expect(CountdownMath.possibleMoments(on: CalendarDay(year: 2027, month: 1, day: 1),
                at: TimeOfDay(hour: 25, minute: 0), in: laZone).isEmpty)
    }

    @Test func skippedMidnightUsesTheFirstInstantOfThatDay() {
        let zone = TimeZone(identifier: "America/Santiago")!
        let result = CountdownMath.validStartOfDay(CalendarDay(year: 2026, month: 9, day: 6), in: zone)
        #expect(result == instant("2026-09-06T04:00:00Z"))
    }

    @Test func offsetsAreComputedAtTheTargetNotAtCreation() {
        let summer = instant("2026-10-01T12:00:00Z")
        let winter = instant("2026-12-19T12:00:00Z")
        #expect(CountdownMath.offsetText(of: tokyoZone, from: laZone, at: summer) == "16h ahead")
        #expect(CountdownMath.offsetText(of: tokyoZone, from: laZone, at: winter) == "17h ahead")
        let nepal = TimeZone(identifier: "Asia/Kathmandu")!
        #expect(CountdownMath.offsetText(of: nepal, from: laZone, at: winter) == "13h 45m ahead")
    }
}

@MainActor struct DraftTimeTests {
    private func draft(day: CalendarDay = CalendarDay(year: 2027, month: 3, day: 14),
                       time: TimeOfDay = TimeOfDay(hour: 9, minute: 40)) -> Draft {
        var draft = Draft(now: instant("2026-10-01T12:00:00Z"), timeZone: laZone)
        draft.name = "Trip"
        draft.dateInput.select(day)
        draft.hasTime = true
        draft.time = time
        return draft
    }

    @Test func choosingChangingAndRemovingAPlaceNeverMovesTheMoment() throws {
        var draft = draft()
        let expected = try #require(draft.countdown)
        #expect(expected.targetDate == instant("2027-03-14T16:40:00Z"))
        draft.hasPlace = true
        #expect(draft.targetDate == expected.targetDate)
        for zone in [tokyoZone, londonZone, TimeZone(identifier: "Asia/Kathmandu")!] {
            draft.place = Place(timeZoneID: zone.identifier, name: "There")
            #expect(draft.countdown?.targetDate == expected.targetDate)
            #expect(draft.countdown?.startDate == expected.startDate)
        }
        draft.hasPlace = false
        #expect(draft.countdown?.targetDate == expected.targetDate)
    }

    @Test func springGapCannotBeSavedOrSilentlyNormalized() {
        let draft = draft(time: TimeOfDay(hour: 2, minute: 30))
        #expect(draft.candidates.isEmpty)
        #expect(draft.targetDate == nil)
        #expect(draft.countdown == nil)
    }

    @Test func repeatedTimeRequiresChoiceAndCanBeChangedWhileEditing() throws {
        var draft = draft(day: CalendarDay(year: 2026, month: 11, day: 1), time: TimeOfDay(hour: 1, minute: 30))
        #expect(draft.targetDate == nil)
        draft.occurrence = instant("2026-11-01T09:30:00Z")
        let saved = try #require(draft.countdown)
        var editing = Draft(editing: saved, timeZone: laZone)
        #expect(editing.countdown == saved)
        editing.name = "Renamed"
        #expect(editing.countdown?.targetDate == saved.targetDate)
        editing.occurrence = instant("2026-11-01T08:30:00Z")
        #expect(editing.countdown?.targetDate == saved.targetDate - 3600)
    }

    @Test func londonTimeSurvivesEditingOnLosAngelesSpringTransition() throws {
        let target = instant("2027-03-14T02:30:00Z")
        let saved = Countdown(name: "London trip", icon: .default, targetDate: target, showsTime: true,
                              place: Place(timeZoneID: londonZone.identifier, name: "London"),
                              startDate: instant("2026-10-01T07:00:00Z"))
        let edit = Draft(editing: saved, timeZone: laZone)
        #expect(edit.dateInput.day == CalendarDay(year: 2027, month: 3, day: 13))
        #expect(edit.time == TimeOfDay(hour: 18, minute: 30))
        #expect(edit.countdown == saved)
        let roundTrip = try JSONDecoder().decode(Countdown.self, from: JSONEncoder().encode(try #require(edit.countdown)))
        #expect(roundTrip.targetDate == target)
    }

    @Test func dateOnlyTargetAndProgressStartSurviveTravelAndRename() throws {
        var draft = draft()
        draft.hasTime = false
        let saved = try #require(draft.countdown)
        #expect(saved.targetDate == instant("2027-03-14T08:00:00Z"))
        for zone in [laZone, londonZone, tokyoZone] {
            var edit = Draft(editing: saved, timeZone: zone)
            edit.name = "Changed name"
            edit.hasPlace = true
            edit.place = Place(timeZoneID: laZone.identifier, name: "Home")
            #expect(edit.countdown?.targetDate == saved.targetDate)
            #expect(edit.countdown?.startDate == saved.startDate)
        }
    }

    @Test func changingSystemZoneDuringEditingConvertsInsteadOfReinterpreting() throws {
        var edit = draft()
        let saved = try #require(edit.countdown)
        edit.changeTimeZone(to: tokyoZone)
        #expect(edit.time == TimeOfDay(hour: 1, minute: 40))
        #expect(edit.dateInput.day == CalendarDay(year: 2027, month: 3, day: 15))
        #expect(edit.countdown == saved)
        edit.changeTimeZone(to: londonZone)
        #expect(edit.countdown == saved)
    }

    @Test func zoneChangePreservesInvalidTextAndItsInputZone() {
        var edit = draft()
        edit.dateInput.text = "2027-02-30"
        edit.changeTimeZone(to: tokyoZone)
        #expect(edit.timeZone == laZone)
        #expect(edit.dateInput.text == "2027-02-30")
        #expect(edit.countdown == nil)
    }

    @Test func saveReadsBothTypedDatesWithoutReturn() throws {
        var edit = draft()
        edit.dateInput.text = "2027-12-19"
        edit.startInput.text = "2026-09-01"
        let result = try #require(edit.validatedCountdown(now: instant("2026-10-01T12:00:00Z")))
        #expect(result.targetDate == instant("2027-12-19T17:40:00Z"))
        #expect(result.startDate == instant("2026-09-01T07:00:00Z"))
        edit.dateInput.text = "2027-12-19 garbage"
        #expect(edit.validatedCountdown(now: instant("2026-10-01T12:00:00Z")) == nil)
    }

    @Test func saveRevalidatesAgainstActualTime() throws {
        let edit = draft()
        let moment = try #require(edit.targetDate)
        #expect(edit.validatedCountdown(now: moment - 1) != nil)
        #expect(edit.validatedCountdown(now: moment) == nil)
        #expect(edit.validatedCountdown(now: moment + 1) == nil)
    }

    @Test func dateOnlyCanBeChangedWithoutKeepingAnOldTarget() throws {
        var edit = Draft(editing: try #require(draft().countdown), timeZone: laZone)
        edit.hasTime = false
        #expect(edit.targetDate == instant("2027-03-14T08:00:00Z"))
        edit.dateInput.text = "2027-03-15"
        #expect(edit.targetDate == instant("2027-03-15T07:00:00Z"))
    }
}

struct DateEntryTests {
    @Test func invalidTextDoesNotFallBackToTheOldDay() {
        let old = CalendarDay(year: 2027, month: 1, day: 1)
        var entry = DateEntry(old)
        entry.text = "2027-02-30"
        #expect(entry.day == nil)
        let committed = entry.commit()
        #expect(!committed)
        #expect(entry.text == "2027-02-30")
        entry.cancelTyping()
        #expect(entry.day == old)
    }

    @Test func unicodeDigitsNeverCrashISOParsing() {
        for input in ["٢٠٢٧-١٢-١٩", "２０２７-１２-１９", "2027-١٢-19"] {
            #expect(DateEntry.parse(input, locale: Locale(identifier: "en_US")) == nil)
        }
    }

    @Test func theFieldsOwnTextReadsBack() {
        let day = CalendarDay(year: 2027, month: 12, day: 19)
        for id in ["en_US", "en_GB", "de_DE", "fr_FR", "es_ES", "ja_JP", "zh_CN", "ko_KR", "ru_RU", "ar_EG"] {
            let locale = Locale(identifier: id)
            #expect(DateEntry.parse(DateEntry.format(day, locale: locale), locale: locale) == day, "\(id)")
        }
        // Editing the day without the weekday is ambiguous, so it's rejected rather than guessed.
        #expect(DateEntry.parse("Sun, Dec 20, 2027", locale: Locale(identifier: "en_US")) == nil)
    }

    @Test func acceptsCompleteDatesAndRejectsPartialOrImpossibleOnes() {
        let us = Locale(identifier: "en_US")
        #expect(DateEntry.parse("2028-02-29") == CalendarDay(year: 2028, month: 2, day: 29))
        #expect(DateEntry.parse("12/19/2027", locale: us) == CalendarDay(year: 2027, month: 12, day: 19))
        #expect(DateEntry.parse("Dec 19, 2027", locale: us) == CalendarDay(year: 2027, month: 12, day: 19))
        for value in ["", "2027-02-29", "2027-13-01", "02/30/2027", "Dec 19", "2027-12-19 extra"] {
            #expect(DateEntry.parse(value, locale: us) == nil)
        }
    }
}
