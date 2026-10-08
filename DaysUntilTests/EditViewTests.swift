import AppKit
import Combine
import SwiftUI
import Testing
@testable import DaysUntil

@MainActor
final class DraftModel: ObservableObject {
    @Published var draft: Draft

    init(_ draft: Draft) {
        self.draft = draft
    }
}

private struct EditHost: View {
    @ObservedObject var model: DraftModel
    var isNew = false
    var offersLaunchAtLogin = false
    var offersNotifications = false
    var deletedName: String?
    var saved = Calls<Countdown>()
    var cancelled = Calls<Void>()

    var body: some View {
        EditView(
            draft: $model.draft, now: Date(), isNew: isNew, makeMenu: { NSMenu() }, offersLaunchAtLogin: offersLaunchAtLogin,
            offersNotifications: offersNotifications,
            deletedName: deletedName, onUndoDelete: {}, onCancel: { cancelled.record(()) }, onSave: saved.record
        )
        .frame(width: 340)
    }
}

/// The form, laid out off screen in each of its shapes.
@Suite @MainActor
struct EditViewTests {
    let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private func draft(_ change: (inout Draft) -> Void = { _ in }) -> DraftModel {
        var draft = Draft(now: Date(), timeZone: .current)
        draft.name = "Trip"
        change(&draft)
        return DraftModel(draft)
    }

    private func height(_ host: EditHost) -> CGFloat {
        let host = OffscreenHost(host, size: CGSize(width: 340, height: 1_200))
        defer { host.close() }
        return host.fittingSize.height
    }

    private func key(_ keyCode: UInt16, _ characters: String) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0, context: nil, characters: characters, charactersIgnoringModifiers: characters,
            isARepeat: false, keyCode: keyCode
        )!
    }

    @Test func eachDateFieldOpensItsCalendarWhileFocused() throws {
        let model = draft()
        let host = OffscreenHost(EditHost(model: model), size: CGSize(width: 340, height: 1_200))
        defer { host.close() }
        let closed = host.fittingSize.height
        let fields = host.views(NSTextField.self)
        for text in [model.draft.dateInput.displayText, model.draft.startInput.displayText] {
            let field = try #require(fields.first { $0.stringValue == text })
            host.window.makeFirstResponder(field)
            host.settle()
            host.settle()
            #expect(host.fittingSize.height > closed + 150, "\(text)")
        }
        // Leaving the date fields closes their calendars.
        host.window.makeFirstResponder(nil)
        host.settle()
        host.settle()
        #expect(host.fittingSize.height == closed)
    }

    @Test func returnSavesAndEscapeCancels() {
        let model = draft()
        let saved = Calls<Countdown>()
        let cancelled = Calls<Void>()
        let host = OffscreenHost(EditHost(model: model, saved: saved, cancelled: cancelled))
        defer { host.close() }
        _ = host.window.performKeyEquivalent(with: key(OffscreenHost.returnKey, "\r"))
        host.settle()
        #expect(saved.values.map(\.name) == ["Trip"])
        #expect(saved.values.first?.targetDate == model.draft.targetDate)
        _ = host.window.performKeyEquivalent(with: key(OffscreenHost.escape, "\u{1B}"))
        host.settle()
        #expect(cancelled.values.count == 1)
    }

    @Test func aNewInstallStartsTheCountdownAndOffersLaunchAtLogin() {
        let model = draft()
        let saved = Calls<Countdown>()
        #expect(height(EditHost(model: model, isNew: true, offersLaunchAtLogin: true)) > height(EditHost(model: model, isNew: true)))
        let host = OffscreenHost(EditHost(model: model, isNew: true, offersLaunchAtLogin: true, saved: saved))
        defer { host.close() }
        _ = host.window.performKeyEquivalent(with: key(OffscreenHost.returnKey, "\r"))
        host.settle()
        #expect(saved.values.count == 1)
    }

    @Test func aNewInstallAlsoOffersNotifications() {
        let model = draft()
        #expect(height(EditHost(model: model, isNew: true, offersLaunchAtLogin: true, offersNotifications: true))
            > height(EditHost(model: model, isNew: true, offersLaunchAtLogin: true)))
    }

    @Test func nothingToSaveWithoutAName() {
        let model = draft { $0.name = "  " }
        let saved = Calls<Countdown>()
        let host = OffscreenHost(EditHost(model: model, saved: saved))
        defer { host.close() }
        _ = host.window.performKeyEquivalent(with: key(OffscreenHost.returnKey, "\r"))
        host.settle()
        #expect(saved.values.isEmpty)
    }

    @Test func onlyTheNewCountdownFormHasTheMoreMenu() {
        func hasMoreButton(_ host: EditHost) -> Bool {
            let host = OffscreenHost(host)
            defer { host.close() }
            return host.views(NSView.self).contains { $0.accessibilityRole() == .menuButton }
        }
        #expect(hasMoreButton(EditHost(model: draft(), isNew: true)))
        #expect(!hasMoreButton(EditHost(model: draft())))
    }

    @Test func afterADeleteTheFormOffersUndo() {
        let model = draft()
        #expect(height(EditHost(model: model, isNew: true, deletedName: "Trip")) > height(EditHost(model: model, isNew: true)))
    }

    @Test func aRepeatedTimeAsksWhichOne() {
        // 1:30 AM happens twice in Los Angeles as the clocks go back on Sun, Nov 1, 2026.
        let now = CountdownMath.gregorian(in: losAngeles).date(from: DateComponents(year: 2026, month: 10, day: 4))!
        func model(_ hour: Int) -> DraftModel {
            var draft = Draft(now: now, timeZone: losAngeles)
            draft.name = "Trip"
            draft.dateInput = DateEntry(CalendarDay(year: 2026, month: 11, day: 1))
            draft.hasTime = true
            draft.time = TimeOfDay(hour: hour, minute: 30)
            return DraftModel(draft)
        }
        #expect(model(1).draft.candidates.count == 2)
        #expect(height(EditHost(model: model(1))) > height(EditHost(model: model(3))))
    }

    @Test func aSecondTimeZoneShowsItsSearch() {
        let plain = draft()
        let withPlace = draft {
            $0.hasPlace = true
            $0.place = Place(timeZoneID: "Asia/Tokyo", name: "Tokyo")
        }
        #expect(height(EditHost(model: withPlace)) > height(EditHost(model: plain)))
    }

    @Test func aDayOffMidnightAfterTravelSaysWhenItCountsTo() throws {
        // A date-only countdown made in Tokyo, read in Los Angeles: its start of day falls mid-afternoon.
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        let day = CountdownMath.startOfDay(CountdownMath.calendarDay(of: Date().addingTimeInterval(86_400 * 30), in: tokyo), in: tokyo)
        let countdown = Countdown(name: "Trip", icon: .default, targetDate: day, showsTime: false, place: nil, startDate: Date())
        let travelled = DraftModel(Draft(editing: countdown, timeZone: losAngeles))
        let athome = DraftModel(Draft(editing: countdown, timeZone: tokyo))
        #expect(height(EditHost(model: travelled)) > height(EditHost(model: athome)))
    }
}
