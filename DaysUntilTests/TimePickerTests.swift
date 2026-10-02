import AppKit
import SwiftUI
import Testing
@testable import DaysUntil

@MainActor struct TimePickerTests {
    @Test func nativePickerCarriesWallTimeInUTCAndUpdatesComponents() throws {
        var time = TimeOfDay(hour: 2, minute: 30)
        let host = NSHostingView(rootView: TimeField(time: Binding(get: { time }, set: { time = $0 })))
        host.frame = NSRect(x: 0, y: 0, width: 180, height: 30)
        host.layoutSubtreeIfNeeded()
        func findPicker(_ view: NSView) -> NSDatePicker? {
            (view as? NSDatePicker) ?? view.subviews.lazy.compactMap(findPicker).first
        }
        let picker = try #require(findPicker(host))
        #expect(picker.timeZone?.secondsFromGMT() == 0)
        #expect(CountdownMath.timeOfDay(of: picker.dateValue, in: .gmt) == time)
        picker.dateValue = CountdownMath.date(CalendarDay(year: 2001, month: 1, day: 1),
                                             at: TimeOfDay(hour: 1, minute: 45), in: .gmt)
        let action = try #require(picker.action)
        #expect(NSApp.sendAction(action, to: picker.target, from: picker))
        #expect(time == TimeOfDay(hour: 1, minute: 45))
    }
}
