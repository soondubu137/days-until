# Days Until — design

A macOS menu bar app that counts down to one distant date: going home, a move, a wedding, a trip. It is not a focus or kitchen timer. It runs for weeks or months, and you glance at it many times a day.

Three principles:

- **Small.** Menu bar space is scarce, and the notch hides overflow.
- **Calm.** No motion until it matters.
- **Livelier as the date nears.** Precision increases as the date gets closer.

## The countdown

The app holds one countdown.

| Field | Required | Notes |
|---|---|---|
| Name | yes | "Going home", "Wedding", "Move to Berlin" |
| Icon | yes | A preset SF Symbol (house, airplane, suitcase, heart, gift, graduation cap, star, calendar) or any emoji. Defaults to house. |
| Date | yes | |
| Exact time | no | Without one, the countdown runs to the start of the day. |
| Place | no | A time zone plus a display name. See [Place](#place). |
| Counting from | yes | Start of the progress bar. Defaults to the day the countdown was created. |

The date and time are stored as components (year, month, day, optional hour and minute) plus an optional time zone identifier. They're resolved to an absolute moment whenever the countdown is computed.

### Place

Place is optional, so countdowns that don't need a second time zone never see it.

- **No place (floating):** the date and time are read in the Mac's current time zone, like an all-day Calendar event. If you travel, the moment moves with you. Dec 19 is Dec 19 wherever you are.
- **With a place (pinned):** the date and time are in the place's time zone. The moment is fixed no matter where the Mac is. This matches how tickets and invitations print times, e.g. "lands 6:40 PM Tokyo time".

With a place set, the popover also shows:

- **The place's current time,** a sun or moon icon for day or night there, and the offset from your time, e.g. "10:41 AM Wed · 13h ahead".
- **The arrival time in both zones:** the place's time and "your time". The second line is hidden when both zones have the same offset.

The place picker searches `TimeZone.knownTimeZoneIdentifiers`, matching both the city part of the identifier (`Asia/Tokyo` → "Tokyo") and the localized zone name ("Japan Standard Time"). The display name defaults to the city and is editable. For example, you can pick `Asia/Shanghai` and call it "Beijing" or just "Home".

### Counting rules

- **Days** are the number of local midnights between now and the moment, counted in the Mac's current calendar and time zone. The number changes at midnight and equals the number of nights left.
- **Exact remaining time** is real elapsed time, so it's correct across daylight saving changes.
- **"The day"** is the local date on which the moment falls. The "Today" state shows on that date.

A pinned date-only countdown starts at midnight at the place, which can fall on the previous day locally. The popover shows both times, so this is visible rather than surprising.

## Menu bar item

The item shows the icon plus text whose precision depends on how close the moment is:

| Time left | Text | Changes |
|---|---|---|
| More than 7 days | `81d` | At local midnight |
| 1 to 7 days | `6d 14h` | Every hour |
| Less than 24 hours | `13:42:07` | Every second |
| Moment reached, same local day | `Today` | — |
| After that day | icon only | — |
| No countdown set | `Set date` | — |

Menu bar styles, chosen in the edit form:

- **Adaptive (default):** follows the table above.
- **Days only**
- **Days and hours**
- **Always show seconds**
- **Icon only:** useful when the notch would hide the item.

Digits are fixed-width (tabular), so the item doesn't shift as numbers change.

## Popover

Clicking the item opens a popover with:

- **Header:** icon and name.
- **Big number:** calendar days left, with the exact remaining time ticking underneath (`80d 07h 58m 13s`).
- **Progress bar:** from "counting from" to the moment, e.g. "75% of the way".
- **Other units:** weeks (one decimal), weekends (Saturdays left) and workdays (Mondays to Fridays left).
- **Place section:** only when a place is set.
- **Arrival:** full date and time.
- **Actions:** Edit countdown, Quit.

After the moment has passed, the popover shows "Reached Dec 19 · 3 days ago" and a "Set new countdown" button. It never counts negative.

On first launch the popover opens straight to the edit form.

## Edit form

The edit form replaces the popover's content rather than opening a separate window, because Settings windows in menu-bar-only apps have unreliable focus.

Closing the popover drops an unsaved edit, so it always reopens on the countdown. On first launch there's nothing to go back to, so the form keeps what was typed.

Fields:

- **Name**
- **Icon**
- **Date**
- **Exact time:** a toggle plus a time picker.
- **Place:** a toggle plus a searchable picker, with a caption "Date and time are in Tokyo time."
- **Counting from**
- **Menu bar style**
- **Launch at login**

Validation:

- **The moment must be in the future:** "Pick a date in the future."
- **Counting from must be before the moment:** "Start date must be before the countdown date."

## Updates and energy

The app runs for months, so it never polls.

- **Menu bar:** after each render, the app works out the exact instant when the visible text will next change and schedules one timer, with tolerance, for that instant. Boundaries depend on the display:
  - days: the next local midnight
  - hours: the next whole hour before the moment
  - seconds: the next whole second before the moment
- **Popover open:** the exact line ticks every second. The place clock updates every minute. Both stop when the popover closes.
- **Recompute immediately** on:
  - wake from sleep (`NSWorkspace.didWakeNotification`)
  - clock changes (`NSSystemClockDidChange`)
  - time zone changes (`NSSystemTimeZoneDidChange`)
  - day changes (`NSCalendarDayChanged`)

## Technical approach

- **Language and UI:** Swift 6. The menu bar item is an AppKit `NSStatusItem`, and clicking it opens an `NSPopover` whose content is SwiftUI. `LSUIElement` is set, so there's no Dock icon.
- **Why not `MenuBarExtra`:**
  - It keeps only the plain text of its label and drops the font, so the digits can't be tabular and the item shifts every second.
  - It has no way to open its window from code, which first launch needs.
- **Focus:** the app activates when the popover opens, so the form's text fields take typing, and hides when it closes, so the keyboard goes back to the app that had it. A hidden Edit menu gives the text fields copy, paste and select all.
- **Minimum macOS: 13 Ventura.**
  - `SMAppService` (launch at login) needs 13, and so does `NSHostingController` resizing the popover to fit its content.
  - `@Observable` needs 14, so state uses `ObservableObject` instead.
  - The current Xcode can't target anything below macOS 12. Supporting 12 would need a separate login-item helper, only to add 2015–2016 Macs, so it isn't worth it.
- **Storage:** `UserDefaults`, with the countdown encoded as JSON under one key and display settings stored alongside.
- **Launch at login:** `SMAppService.mainApp`.
- **Project:** a plain Xcode project, committed to git. It uses folder-synchronized groups (Xcode 16+), so adding or removing source files doesn't change the project file. No project generator or package manager is needed.

### Structure

```
DaysUntil/
  App/        app entry, status item and popover, menu bar clock
  Model/      Countdown (data), CountdownMath (pure calculations), Store (persistence)
  Views/      MenuBarLabel, PopoverView, EditView, PlacePicker
DaysUntilTests/
```

All date calculations live in `CountdownMath`, which has no UI or system dependencies and takes `now`, the calendar and the time zone as inputs.

Unit tests cover:

- **Day counting across midnight:** the local-midnight rule for days left.
- **Daylight saving transitions:** exact remaining time stays correct across them.
- **Floating vs pinned:** each when the Mac's time zone changes.
- **Date-only vs timed:** both kinds of countdown.
- **Past moments:** the Today state and after.
- **Display text at each threshold:** the adaptive menu bar table.
- **Next-change instant:** the timer boundary for each display.

## Later

These are out of scope for the first version:

- **Milestone notifications:** 100 days, 1 month, 1 week, tomorrow. They'd be scheduled up front with `UNCalendarNotificationTrigger`, so the app doesn't need to be awake.
- **A desktop widget:** WidgetKit.
- **More than one countdown,** with one pinned to the menu bar.
