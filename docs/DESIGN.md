# Days Until — design

A macOS menu bar app that counts down to one distant date: going home, a move, a wedding, a trip. It is not a focus or kitchen timer. It runs for weeks or months, and you glance at it many times a day.

Three principles:

- **Small.** Menu bar space is scarce, and the notch hides overflow.
- **Calm.** No motion until it matters.
- **Livelier as the date nears.** Precision increases as the date gets closer.

It should feel like part of macOS: Liquid Glass, the person's own accent colour, system fonts, SF Symbols and standard controls. Custom work goes only where the system has nothing that fits, like the calendar. Colour is spent only where the date is close. The visual design is in the Figma file [Days Until — UI Design](https://www.figma.com/design/sOUEb341mIYq9Fx0L3QS2c).

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
| Moment reached, same local day | `Today` on an accent capsule | — |
| After that day | icon only | — |
| No countdown set | calendar icon plus `Set date` | — |

Symbols are template images, so they follow the menu bar over any wallpaper. The Today capsule is the one coloured state: it fills with the system accent until local midnight. An emoji icon keeps its own colour.

Menu bar styles, chosen in the popover's ••• menu:

- **Adaptive (default):** follows the table above.
- **Days only**
- **Days and hours**
- **Always show seconds**
- **Icon only:** useful when the notch would hide the item.

Digits are fixed-width (tabular), so the item doesn't shift as numbers change.

## Popover

Clicking the item opens a popover, 340 pt wide. It's Liquid Glass on macOS 26 (see [Background](#background)).

- **Header:** the icon on an accent tile, the name, and a ••• button.
- **Big readout:** follows the adaptive menu bar ladder, so it never shows less precision than the item. More than a week out, calendar days left (`80 days`). In the final week, days and hours (`5 days 16 hours`). In the final 24 hours, a seconds clock (`13:42:07`) in the accent colour, and the icon tile fills with the accent.
- **The line under it:** for a timed countdown, the exact time left, ticking (`80d 01h 58m 13s`), or "Until 9:40 AM tomorrow" on the final day. For a date-only countdown, the date itself ("Saturday, April 24, 2027"), since an exact line would always read a day less than the count.
- **Runway:** replaces a progress bar. One tick per day from Counting from to the day: elapsed days short and faint, weekends ahead taller, today an accent tick with a dot, and the countdown's icon waiting at the end. Month names mark the first of each month. Spans longer than 26 weeks tick once a week, with the weeks holding the first of a month taller. The final 24 hours tick once an hour, with midnight taller. Underneath: "41% of the way" and "Counting from Mon, Aug 3", or "One tick a week · from Jun 1", or "Final 24 hours" and "One tick an hour".
- **Other units:** weeks (one decimal), weekends (Saturdays left) and workdays (Mondays to Fridays left). Hidden on the final day.
- **When and where, in one box:** the arrival in the place's time and "your time" (the second line is hidden when both zones have the same offset), and the place's clock. A floating date-only countdown has no box, since its date is already under the count.

On the day itself the readout is `Today` in the accent colour, with "Reached at 9:40 AM · 6:40 PM in Tokyo". The runway is complete and drawn in the accent, and its destination fills.

After that day, the popover shows "Reached Fri, Dec 18", "3 days ago", the finished runway ("All the way", "137 days from Mon, Aug 3") and a "Set New Countdown…" button, which keeps the name, icon and place. It never counts negative.

### The ••• menu

App settings live here, not in the form, and apply at once like any Mac menu. It's an ordinary `NSMenu`:

- **Edit Countdown…** ⌘E
- **Menu Bar ▸** the five styles, each showing what the item would read with it right now.
- **Background ▸** Liquid Glass or Solid. macOS 26 only.
- **Launch at Login**
- **Quit Days Until** ⌘Q

⌘E and ⌘Q also work while the popover is open and the menu isn't.

### Background

On macOS 26 the popover is Liquid Glass by default, and Solid is one click away in the ••• menu, for people who find glass busy over a bright or detailed wallpaper. On macOS 13 to 15 there's no choice: the popover is always Solid. The setting is saved as `popoverBackground` and ignored before macOS 26, so upgrading later brings glass back as the default.

Only the popover's background changes, with its grouped boxes and fields. Menus, the menu bar, switches, buttons and the accent are drawn by macOS in the style of the system it runs on. Corner radii follow the system too: capsule fields and circular icon wells on macOS 26, smaller rounded rectangles before.

## Edit form

The edit form replaces the popover's content rather than opening a separate window, because Settings windows in menu-bar-only apps have unreliable focus.

Closing the popover drops an unsaved edit, so it always reopens on the countdown. On first launch there's nothing to go back to, so the form keeps what was typed.

Three groups:

- **What:** the name, and the icon as one row of wells: the preset symbols, then a well that opens the system emoji picker.
- **When:** the date, then optional fields as switches that reveal their value in place. **Exact time** shows a time field beside its switch. **In another time zone** shows a search inside the group, with each result's time now, so zones can be told apart. Once a place is picked, its name is editable. A footnote converts the time to yours: "Date and time are in Tokyo time. 6:40 PM there is 9:40 AM for you."
- **Progress:** Counting from, with "Progress is measured from this day."

Dates open our own calendar inside the group, under the field. SwiftUI's graphical date picker can't be styled, disable single days or say what a choice means, so the form uses its own, drawn like the system's:

- **Six weeks, always,** so paging months never moves the rows below.
- **Only valid days.** For the countdown date, days whose moment would already be past are disabled. For Counting from, days on or after the moment are.
- **Today's number** takes the accent colour, and the chosen day is a filled accent circle. Weekends are secondary.
- **It says what the choice means:** "Friday, December 18 · 80 days from today", or "Monday, August 3 · 137 days before Fri, Dec 18".
- **Keyboard:** the arrow keys move by day and week, Page Up and Page Down by month, T jumps to today, Return picks and Esc closes. The field still takes typing: any date the system can read, picked with Return.
- **Localised:** the week starts on the locale's first weekday, and the names come from the system.

On first launch the popover opens by itself, titled "New Countdown", with the name focused. The date is a month out, counting from today. The form also offers "Open Days Until at login", on by default, Quit, and "Start Countdown", which enables once there's a name.

Validation messages sit under the field they're about, and Save stays disabled until they're fixed:

- **The moment must be in the future:** "Pick a date in the future."
- **Counting from must be before the moment:** "Pick a day before Fri, Dec 18."

## Updates and energy

The app runs for months, so it never polls.

- **Menu bar:** after each render, the app works out the exact instant when the visible text will next change and schedules one timer, with tolerance, for that instant. Boundaries depend on the display:
  - days: the next local midnight
  - hours: the next whole hour before the moment
  - seconds: the next whole second before the moment
- **Popover open:** the readout ticks every second. The place clocks update every minute. Both stop when the popover closes.
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
- **Focus:** the app activates when the popover opens, so the form's text fields take typing, and hides when it closes, so the keyboard goes back to the app that had it. A hidden main menu gives the text fields copy, paste and select all, and the popover ⌘E and ⌘Q.
- **Appearance:** the popover follows Light or Dark Mode explicitly. Left alone it would take the menu bar's appearance, which on macOS 26 follows the wallpaper.
- **Opening and closing:** the popover moves like the system's menu bar menus, as measured on Wi-Fi, Sound and Battery in macOS 26. It opens on mouse down and appears at once, and the item sits on a highlight capsule while it's open. After Esc or a click on the item it fades out, window opacity only, linear, over 0.24 s. The highlight goes, without fading, as the fade starts, and a click on the item mid-fade brings both straight back. After a click anywhere else it vanishes at once. NSPopover's own animation, which grows out of the arrow and shrinks back into it, is off. Opening on mouse down also keeps the button's click from clearing the highlight just after the popover opens. The app takes every click on the item itself, on mouse down, so a quick double click opens and closes the popover. Left to NSPopover, the second click of a double click went to the button, which could drop it, and the popover stayed open.
- **Solid background:** on macOS 14 and later the popover has `hasFullSizeContent` on, set once, so its content reaches under the arrow while laying out inside the safe area. The Solid panel is a SwiftUI background that ignores the safe area, so it covers the whole popover, arrow included. Changing `hasFullSizeContent` while the popover is shown leaves it the wrong size, so Liquid Glass keeps it on and simply draws no background. macOS 13 lacks the property, so there the arrow keeps the system's material.
- **Keyboard in the form:** macOS 13 has no `onKeyPress`, so the calendar and the place search read keys with a local event monitor while they're on screen.
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
  App/        app entry, status item and popover, the ••• menu, menu bar clock
  Model/      Countdown (data), CountdownMath (pure calculations), Store (persistence)
  Views/      MenuBarLabel, PopoverView, CountdownView, RunwayView, EditView, CalendarField,
              PlacePicker, FormControls, Theme (colour tokens and radii)
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
- **The popover's readout and runway:** the precision ladder, and ticks per day, week and hour.

## Later

These are out of scope for the first version:

- **Milestone notifications:** 100 days, 1 month, 1 week, tomorrow. They'd be scheduled up front with `UNCalendarNotificationTrigger`, so the app doesn't need to be awake.
- **A desktop widget:** WidgetKit.
- **More than one countdown,** with one pinned to the menu bar.
