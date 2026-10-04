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

The target and progress start are stored as absolute instants (`Date` timestamps), with a versioned persistence format. They never move when the Mac's time zone, locale, daylight-saving offset, or auxiliary place changes. The editor accepts Gregorian date and time components in the Mac's local zone and resolves them once when saved. A date-only target resolves to the first instant of the selected local day when it is created; it is fixed thereafter too.

Version 1 data is migrated once, preserving the old app's effective target and start instants. An old place-defined target keeps that instant, then becomes display-only. An old floating target is resolved in the Mac's zone at migration because its original creation zone was not recorded. The original JSON is retained at `countdown.v1.backup`. Simply opening and saving an edit preserves the instants, including repeated times and targets that are no longer midnight after travel.

### Place

Place is optional, so countdowns that don't need a second time zone never see it.

- **Input:** date and time are always in the Mac's local zone.
- **Auxiliary display:** choosing, changing or removing a place never changes the target. It only shows the same instant in another zone.
- **Travel:** opening an edit converts the fixed target to the Mac's current local zone. A valid open draft is converted too when the system zone changes. Invalid pending text stays in its labelled input zone until corrected, so it is never silently reinterpreted. When Exact time is off, its hidden hour/minute fields remain unchanged as inactive input preferences. Enabling it uses those visible fields in the labelled input zone and revalidates gaps and repeated times; the date-only target and progress start remain fixed through travel.

With a place set, the popover also shows:

- **The place's current time,** a sun or moon icon for day or night there, and the offset from your time, e.g. "10:41 AM Wed · 13h ahead".
- **The arrival time in both zones:** "Your time" first, then the auxiliary place, with a date on each line so crossing midnight or a year boundary is explicit. Conversion uses the offset at the target instant, not today's offset.

The place picker searches `TimeZone.knownTimeZoneIdentifiers`, matching both the city part of the identifier (`Asia/Tokyo` → "Tokyo") and the localized zone name ("Japan Standard Time"). The place is shown by its city in the app's language ("上海" in Japanese), and only a search result can become the place.

### Counting rules

- **Days** are the number of local dates between now and the moment, counted in the Mac's current calendar and time zone. The number changes at midnight and equals the number of nights left, even across a day whose midnight daylight saving skips. Before the day itself it is never fewer than the whole days of real time left: when the clocks go back, seven days of real time can span six nights, and the count would otherwise rise as it reached the final week's `7d 0h`. In that case it drops when the whole day of real time runs out, not at midnight.
- **Exact remaining time** is real elapsed time, so it's correct across daylight saving changes. Seconds round up so zero is never shown before the target. Hours are the whole hours in those seconds, so the hours, the seconds clock and the ticking line always agree: exactly 7 days reads `7d 0h` until `6d 23h 59m 59s` is left, and exactly 24 hours reads `24:00:00` in the seconds clock.
- **Today/tomorrow text** follows calendar dates, not 24-hour intervals. Spring-forward can put the day after tomorrow less than 24 hours away; in that case the exact local date is shown.
- **"The day"** is the local date on which the moment falls. The "Today" state shows on that date.

A date-only target may no longer be midnight after travel. In that case its local time is displayed too; the saved instant still does not move.

## Menu bar item

The item shows the icon plus text whose precision depends on how close the moment is:

| Time left | Text | Changes |
|---|---|---|
| More than 7 days | `81d` | At local midnight |
| 1 to 7 days | `6d 14h` | Every hour |
| Less than 24 hours | `13:42:07` | Every second |
| Moment reached, same local day | `Today`, the icon in the accent | — |
| After that day | icon only | — |
| No countdown set | calendar icon plus `Set date` | — |

The icon is a template image and the text is the button's title, so both follow the menu bar over any wallpaper, and the text is drawn exactly as the clock's is. On the day itself, until local midnight, the symbol takes the system accent: the one coloured state. It has no background, since a tint takes on the wallpaper's colour, and "Today" stays in the label colour. An emoji icon keeps its own colour.

Menu bar styles, chosen in the popover's ••• menu:

- **Adaptive (default):** follows the table above.
- **Days only**
- **Days and hours**
- **Always show seconds**
- **Icon only:** useful when the notch would hide the item.

### Layout

The text is the button's title, and the icon an image of its own, placed by what's drawn. Text drawn into an image came out thinner than the clock's beside it. A symbol's own image doesn't work either: the menu bar centres a symbol's whole image, margins included, which hung the icon below the text, and spaced the two by each symbol's own margins.

- **One baseline.** The text sits where the menu bar sets every title, the clock's and the battery's included: its baseline 4 pt below the midline. A symbol sits on that baseline, the way SF Symbols are drawn to sit in a line of text; an emoji is centred on the cap height. The icon falls on whole pixels.
- **Spacing by what's drawn.** 5 pt between the icon and the text, measured between the drawn shapes, so every icon is the same distance from its text. 2 pt beyond the button's image-only margins on either side, which leaves the icon as far from its neighbours as the system's icons are from each other. With a title, the button's margins are that much wider already.
- **Units closer than words.** The space between `48d` and `10h` is 3 pt, narrower than a word space, so the units read as one figure and stay closer to each other than to the icon.
- **Figures.** In a ticking clock (`13:42:07`), digits are fixed-width so the seconds don't shift the item. Elsewhere they keep their natural widths, which space better (`10h`, not `1 0h`). The text then changes width at most once an hour.

## Popover

Clicking the item opens a popover, 340 pt wide. It's Liquid Glass on macOS 26 (see [Background](#background)). It's shaped and placed like the system's own menu bar menus, as measured on Wi-Fi's in macOS 26: no arrow, its top edge against the menu bar, its left edge in line with the item's highlight capsule, and 16 pt corners all round (10 pt before macOS 26). While it's open it moves with the item, which grows to the left as its text does, from `48d` to `6d 14h`. Near the screen's edge it moves over to stay on screen.

- **Header:** the icon on an accent tile, the name, and a ••• button.
- **Big readout:** follows the adaptive menu bar ladder, so it never shows less precision than the item. More than a week out, calendar days left (`80 days`). In the final week, days and hours (`5 days 16 hours`). In the final 24 hours, a seconds clock (`13:42:07`) in the accent colour, and the icon tile fills with the accent.
- **The line under it:** for a timed countdown, the exact time left, ticking (`80d 01h 58m 13s`), or "Until 9:40 AM tomorrow" on the final day. For a date-only countdown, the date itself ("Saturday, April 24, 2027"), since an exact line would always read a day less than the count.
- **Runway:** replaces a progress bar. One tick per day from Counting from to the day: elapsed days short and faint, weekends ahead taller, today an accent tick with a dot, and the countdown's icon waiting at the end. Month names mark the first of each month. Spans longer than 26 weeks tick once a week, with the weeks holding the first of a month taller. The final 24 hours tick on real clock hours, with the first instant of each local day taller. If midnight is skipped, the real day start is included and labelled, even when it is not a whole hour; a repeated midnight marks and labels only one day start. On a 25-hour day the target's own day can begin with more than 24 hours left; until the final 24 hours, today's mark waits at the destination. Underneath: "41% of the way" and "Counting from Mon, Aug 3", or "Final 24 hours" alone.
- **Other units:** weeks (one decimal), weekends (Saturdays left) and weekdays (Mondays to Fridays left; holidays are included). Hidden on the final day.
- **When and where, in one box:** the arrival in "Your time" first and the auxiliary place second, followed by the place's current clock. A date-only countdown has no box only when its target still falls at local midnight and no place is selected.

On the day itself the readout is `Today` in the accent colour, with one line under it: "Reached at 9:40 AM · 6:40 PM in Tokyo". It's today, so the line gives times, not dates. A date-only countdown still at midnight gives its day instead ("Reached Fri, Dec 18"), and the place's time adds its weekday only when the moment fell on another day there ("Reached at 9:40 PM · Sat 6:40 AM in Tokyo"). The runway is complete and drawn in the accent, and its destination fills.

Each time the popover opens on the day itself, it celebrates with confetti:

- **Every open, until midnight.** Once it has fallen, the popover rests in the plain Today state. If the clock reaches zero while the popover is open, the confetti plays then.
- **Over the popover, never the desktop.** About 90 pieces leave from under the item, fan out and fall out of the bottom edge, clipped to the popover. They never take a click, so the popover works at once.
- **2.5 s in all:** a burst that slows over about 0.3 s, a fall with a sway, then a fade over the last 0.5 s. Strips flip like paper as they fall, alongside squares, dots and thin streamers.
- **System colours:** red, orange, yellow, green, teal, purple, pink and the accent.
- **Reduce Motion:** no confetti.

After that day, the popover shows "Reached Fri, Dec 18", "3 days ago", the finished runway ("All the way", "137 days from Mon, Aug 3") and a "Set New Countdown…" button, which keeps the name, icon and place. It never counts negative.

### The ••• menu

App settings live here, not in the form, and apply at once like any Mac menu. It's an ordinary `NSMenu`:

- **Edit Countdown…** ⌘E
- **Delete Countdown…**: the popover asks first, in the countdown's place, laid out like a macOS 26 alert: the countdown's icon, "Delete “Going home”?", its day, and Cancel and Delete side by side at equal widths. Not an alert itself, which from a popover would be a window of its own. Delete is the system button with its title in red, since the red-tinted one is private to alerts, and as in macOS's alerts it isn't the default button, so Return can't delete. Esc cancels, and so does closing the popover. The ellipsis is for the question, as on Finder's Empty Trash…. Delete goes back to no countdown: the item reads `Set date` and the New Countdown form takes the popover's place, with one quiet line under its title, "Deleted “Going home”." and **Undo**, until the popover closes or a new countdown starts. Not "Cancel", which the form uses for discarding an edit.
- **Menu Bar ▸** the five styles, each showing what the item would read with it right now.
- **Background ▸** Liquid Glass or Solid. macOS 26 only.
- **Launch at Login**, checked once macOS confirms it, and mixed while it waits for approval. If macOS refuses a change or wants approval, one quiet line under the popover says so, with Try Again or Open Settings…; macOS's reason is its tooltip. While a change has failed, **Login Items Settings…** follows it here.
- **About Days Until**: the standard About panel, where every Mac app keeps its version. It shows the icon, the name, "Version 0.1.3 (4)", the copyright and the licence. The popover closes first. Closing the panel, with ⌘W too, hands the keyboard back.
- **Quit Days Until** ⌘Q

⌘E and ⌘Q also work while the popover is open and the menu isn't.

### Background

On macOS 26 the popover is Liquid Glass by default, and Solid is one click away in the ••• menu, for people who find glass busy over a bright or detailed wallpaper. On macOS 13 to 15 there's no choice: the popover is always Solid. The setting is saved as `popoverBackground` and ignored before macOS 26, so upgrading later brings glass back as the default.

Only the popover's background changes, with its grouped boxes and fields. Menus, the menu bar, switches, buttons and the accent are drawn by macOS in the style of the system it runs on. Corner radii follow the system too: capsule fields and circular icon wells on macOS 26, smaller rounded rectangles before.

## Edit form

The edit form replaces the popover's content rather than opening a separate window, because Settings windows in menu-bar-only apps have unreliable focus.

Closing the popover preserves an unsaved edit, including typed dates. Reopening resumes the form. Cancel explicitly discards the draft. On first launch the form also keeps what was typed.

Three groups, with no explanatory footnotes: labels, values and validation messages carry the meaning.

- **What:** the name, and the icon as one row of wells: the preset symbols, then a well that opens our own emoji picker inside the group, under the wells.
- **When:** the date, then optional fields as switches that reveal their value in place. **Exact time** shows a time field beside its switch. **Second time zone** shows a search inside the group, with each result's time now. Once a place is picked, the field shows it with the moment there ("Thu 06:00"), and searches again from its name while it has focus. Return picks the highlighted result and never saves the form; Escape or leaving the field keeps the place. The place never defines the input zone. A date-only target that is no longer midnight after travel gets one line under the group: "Counts down to 17:00 your time."
- **Progress:** Counting from.

Dates open our own calendar inside the group, under the field. SwiftUI's graphical date picker can't be styled, disable single days or say what a choice means, so the form uses its own, drawn like the system's:

- **Six weeks, always,** so paging months never moves the rows below.
- **Only valid days.** A timed countdown allows choosing any day that has not ended, so a DST gap can be corrected in the time field. A date-only countdown requires its start of day to be in the future. Counting from must precede the target instant; the same day is allowed when its start precedes the exact target time.
- **Today's number** takes the accent colour, and the chosen day is a filled accent circle. Weekends are secondary.
- **It says what the choice means:** "Friday, December 18 · in 80 days", or "Monday, August 3 · 137 days before".
- **Keyboard:** the arrow keys move by day and week, Page Up and Page Down by month, T jumps to today, Return picks and Esc closes. The field accepts complete localized dates with a year or ISO dates (`2027-12-19`). Return or leaving the field commits valid input; clicking Save also reads pending text. Invalid text remains visible with an error and disables Save. Esc explicitly cancels pending text.
- **Localised:** the week starts on the locale's first weekday, and the names come from the system. The grid stays Gregorian to match the stored input components; neutral UTC picker values prevent DST normalization.

The emoji picker is our own because the system's can't be used from the popover. Opened at a text caret, Apple's picker takes activation when clicked, and after the pick hands it, with the emoji, to the last regular app, skipping a menu bar app. So the emoji never arrived and was typed into whatever app was in front before. Ours:

- **Every emoji Unicode lists,** in the categories and order of Apple's picker, without skin tone variants. The list is `DaysUntil/Resources/Emoji.tsv`, built by `scripts/make-emoji-list.py` from Unicode's `emoji-test.txt` and CLDR's English annotations. Emoji newer than the Mac, which Apple Color Emoji can't draw as one, are dropped when the list loads.
- **Search** by name and keyword ("home" finds 🏠), whole words before prefixes, single emoji before sequences.
- **A bar** under the grid jumps to each category.
- **Keyboard:** typing searches, the arrow keys move through the emoji, Return picks, and Esc clears the search, then closes. Picking an emoji, a preset symbol, or another field closes it.

On first launch the popover opens by itself, titled "New Countdown", with the name focused. The date is a month out, counting from today. The form also offers "Launch at login", on by default, Quit, and "Start Countdown", which enables once there's a name.

After the countdown is deleted, the form is the same without "Launch at login", which the ••• menu has set by then, and the app doesn't open it by itself at launch: the menu bar item's `Set date` asks instead. Whether a countdown has ever been started is saved as `isSetUp`.

Validation messages sit under the field they're about, and Save stays disabled until they're fixed:

- **The moment must be in the future:** checked again at the actual Save click, not just the last UI tick.
- **Counting from must be before the moment.**
- **Invalid dates and nonexistent local times:** rejected rather than silently normalized (Feb 30, spring-forward gaps, skipped civil days).
- **Repeated local times:** a Repeated time picker distinguishes First and Second, with their UTC offsets. A new ambiguous input requires a choice. Editing preserves an existing occurrence unless explicitly changed.
- **Time-only picker:** stores hour/minute components on a neutral UTC date, independent of the target date's DST behavior.

## Updates and energy

The app runs for months, so it never polls.

- **Menu bar:** after each render, the app works out the exact instant when the visible text will next change and schedules one timer, with tolerance, for that instant. Boundaries depend on the display:
  - days: the next local midnight, or the second a whole day of real time runs out when the clocks have gone back
  - hours: the second that leaves less than the current whole hours
  - seconds: the next whole second before the moment
- **Popover open:** the readout ticks every second. The place clocks update every minute. Both stop when the popover closes. The confetti is the only animation that runs every frame, for its 2.5 s, and it stops if the popover closes.
- **Recompute immediately** on:
  - wake from sleep (`NSWorkspace.didWakeNotification`)
  - clock changes (`NSSystemClockDidChange`)
  - time zone changes (`NSSystemTimeZoneDidChange`)
  - day changes (`NSCalendarDayChanged`)

## Technical approach

- **Language and UI:** Swift 6. The menu bar item is an AppKit `NSStatusItem`, and clicking it opens a borderless `NSPanel` whose content is SwiftUI. Not an `NSPopover`, which points an arrow at the item and leaves a gap under the menu bar. `LSUIElement` is set, so there's no Dock icon.
- **Why not `MenuBarExtra`:**
  - It keeps only the plain text of its label and drops the font, so the digits can't be tabular and the item shifts every second.
  - It has no way to open its window from code, which first launch needs.
- **Focus:** the app activates when the popover opens, so the form's text fields take typing, and hides when it closes, so the keyboard goes back to the app that had it. After a click in another app, that app takes the keyboard itself. A hidden main menu gives the text fields copy, paste and select all, and the popover ⌘E and ⌘Q.
- **Appearance:** the popover follows Light or Dark Mode, as any window of the app does, not the menu bar's appearance, which on macOS 26 follows the wallpaper.
- **Opening and closing:** the popover moves like the system's menu bar menus, as measured on Wi-Fi, Sound and Battery in macOS 26. It opens on mouse down and appears at once, and the item sits on a highlight capsule while it's open. After Esc or a click on the item it fades out, window opacity only, linear, over 0.24 s. The highlight goes, without fading, as the fade starts, and a click on the item mid-fade brings both straight back. After a click anywhere else it vanishes at once, with the ••• menu or a text field's menu if one is open. The app does this itself: the popover closes when the app becomes inactive, and on any click in another app, since with a menu open the app becomes inactive only after the menu has faded out, and a click on a window behind the active app's left the popover open even without one. Clicks in other apps are watched only while the popover is open, which needs no permission, since only key presses would. A click on the item while a menu is open ends the menu, which keeps the click, so the popover fades out once the menu has. Opening on mouse down also keeps the button's click from clearing the highlight just after the popover opens. The app takes every click on the item itself, on mouse down, so a quick double click opens and closes the popover. Left to the button, the second click of a double click could be dropped, and the popover stayed open.
- **The popover's window:** a borderless, non-activating panel, as NSPopover's own window is, so it takes the keyboard as the key window whether or not the window server lets the app activate. It sits at the level of the system's menu bar menus, just under the menu bar. Its content view clips to the rounded corners. On macOS 26 an `NSGlassEffectView` lies under the content, as in NSPopover, and the Solid panel is a SwiftUI background over it; before macOS 26 there's no glass. The content's size constraints resize the window as the content changes, keeping its top edge in place. Esc reaches the panel as `cancelOperation(_:)` unless a Cancel button or a field takes it first.
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
  Model/      Countdown (data), CountdownMath (pure calculations), Draft, DateEntry, Store (persistence)
  Views/      MenuBarLabel, PopoverView, CountdownView, RunwayView, ConfettiView, EditView,
              CalendarField, PlacePicker, FormControls, Theme (colour tokens and radii)
DaysUntilTests/
```

All date calculations live in `CountdownMath`, which has no UI or system dependencies and takes `now`, the calendar and the time zone as inputs.

Unit tests cover:

- **Day counting across midnight:** the local-midnight rule for days left.
- **Daylight saving transitions:** exact remaining time stays correct; strict input rejects gaps, distinguishes repeated hours and half-hours, and handles skipped midnights and civil dates.
- **Absolute instants:** timed and date-only targets and progress starts survive system and auxiliary time-zone changes, editing, persistence and legacy migration. Editing and persistence are checked in every known system time zone, including subsecond precision.
- **Transition invariants:** every known zone is sampled around each system-reported transition from 2026 through 2030. The original instant must remain a valid resolution of its local fields, and day-end timers must advance. Runway tests independently enumerate real minutes across one-hour and half-hour transitions, skipped midnight and repeated midnight.
- **Inactive exact time:** changing zones preserves hidden clock fields; enabling them requires valid input and an explicit occurrence for repeated times.
- **Date-only vs timed:** both kinds of countdown.
- **Past moments:** the Today state and after.
- **Deleting:** the question first, which Cancel or closing the popover ends, then Undo until the popover closes, and no first-launch greeting or launch-at-login change afterwards.
- **Display text at each threshold:** the adaptive menu bar table.
- **Next-change instant:** the timer boundary for each display.
- **The popover's readout and runway:** the precision ladder, and ticks per day, week and hour.

## Later

These are out of scope for the first version:

- **Milestone notifications:** 100 days, 1 month, 1 week, tomorrow. They'd be scheduled up front with `UNCalendarNotificationTrigger`, so the app doesn't need to be awake.
- **A desktop widget:** WidgetKit.
- **More than one countdown,** with one pinned to the menu bar.
- **A name of your own for the place,** e.g. `Asia/Shanghai` called "Home". The place's field used to double as its name, so it looked like a search but took any text; it's now only a search, and the place is shown by its city. A name would need a control of its own, apart from the search. Places saved with a name before keep it.
