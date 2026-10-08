import AppKit
import SwiftUI
import Testing
@testable import DaysUntil

@MainActor struct TimePickerTests {
    @Test func nativePickerCarriesWallTimeInUTCAndUpdatesComponents() throws {
        var time = TimeOfDay(hour: 2, minute: 30)
        let host = NSHostingView(rootView: TimeField(time: Binding(get: { time }, set: { time = $0 }), isOpen: .constant(false)))
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

    @Test func hoursAreNumberedAsTheFieldWritesThem() {
        let us = TimeLabels(locale: Locale(identifier: "en_US"))
        #expect(us.isTwelveHour)
        #expect(us.hours(around: 9) == Array(0..<12))
        #expect(us.hours(around: 18) == Array(12..<24))
        #expect(us.hours(around: 9).map(us.label(hour:)) == ["12", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"])
        #expect(us.label(hour: 21) == "9")

        let britain = TimeLabels(locale: Locale(identifier: "en_GB"))
        #expect(!britain.isTwelveHour)
        #expect(britain.hours(around: 9) == Array(0..<24))
        #expect(britain.label(hour: 0) == "00")
        #expect(britain.label(hour: 23) == "23")

        // The hour alone is "9时" in Chinese, where the field writes "09:40".
        #expect(TimeLabels(locale: Locale(identifier: "zh_CN")).label(hour: 9) == "09")
        #expect(TimeLabels(locale: Locale(identifier: "ja_JP")).label(hour: 9) == "9")
        // Japanese on a 12-hour clock counts 0 to 11.
        var components = Locale.Components(identifier: "ja_JP")
        components.hourCycle = .zeroToEleven
        let japanese = TimeLabels(locale: Locale(components: components))
        #expect(japanese.isTwelveHour)
        #expect(japanese.label(hour: 0) == "0")
        #expect(japanese.label(hour: 12) == "0")

        let taiwan = TimeLabels(locale: Locale(identifier: "zh_TW"))
        #expect(taiwan.isTwelveHour)
        #expect(taiwan.amSymbol == "上午")
        #expect(taiwan.pmSymbol == "下午")
    }

    @Test func aTwelveHourClockSwitchesHalvesWithTheSystemsControl() throws {
        var time = TimeOfDay(hour: 9, minute: 40)
        let host = OffscreenHost(HoursAndMinutes(
            time: Binding(get: { time }, set: { time = $0 }), close: {}, labels: TimeLabels(locale: Locale(identifier: "en_US"))
        ).frame(width: 308))
        defer { host.close() }
        let control = try #require(host.views(NSSegmentedControl.self).first)
        #expect(control.selectedSegment == 0)
        control.selectedSegment = 1
        #expect(NSApp.sendAction(try #require(control.action), to: control.target, from: control))
        host.settle()
        #expect(time == TimeOfDay(hour: 21, minute: 40))
    }

    @Test func minutesComeEveryFive() {
        let us = TimeLabels(locale: Locale(identifier: "en_US"))
        #expect(TimeLabels.minutes == [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55])
        #expect(TimeLabels.minutes.map(us.label(minute:)).prefix(3) == ["00", "05", "10"])
        #expect(us.spoken(minute: 40) == "40 minutes")
        #expect(us.spoken(hour: 21).hasPrefix("9"))
        #expect(us.spoken(hour: 21).hasSuffix("PM"))
    }
}
