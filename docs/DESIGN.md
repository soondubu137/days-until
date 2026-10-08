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
- **Runway:** replaces a progress bar. Ticks from Counting from to the day: elapsed ones short and faint, today an accent mark with a dot, and the countdown's icon waiting at the end. It counts in the finest unit whose ticks stay at least 4 pt apart across its width, so it's never crowded:
  - **Days,** with weekends ahead taller.
  - **Weeks,** with the weeks holding the first of a month taller.
  - **Months,** with each January taller.
  - **Years.**

  On the popover's 278 pt track that's up to 69 days, then 69 weeks, then 69 months. The span's ends are fixed, so the unit never changes as the days pass. Today's mark sits where now really is, so it agrees with the percentage under it, but never past the edges of today's own tick. Month names mark the first of each month, thinning to every second, third or sixth month, then to the years, every second, fifth or tenth year. The final 24 hours tick on real clock hours, with the first instant of each local day taller. If midnight is skipped, the real day start is included and labelled, even when it is not a whole hour; a repeated midnight marks and labels only one day start. On a 25-hour day the target's own day can begin with more than 24 hours left; until the final 24 hours, today's mark waits at the destination. Underneath: "41% of the way" and "Counting from Mon, Aug 3", or "Final 24 hours" alone.
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

App settings live here, not in the form, and apply at once like any Mac menu. It's an ordinary `NSMenu` in three groups: the countdown, then how the app looks and what it does by itself, then the app itself:

- **Edit Countdown…** ⌘E
- **Delete Countdown…**: the popover asks first, in the countdown's place, laid out like a macOS 26 alert: the countdown's icon, "Delete “Going home”?", its day, and Cancel and Delete side by side at equal widths. Not an alert itself, which from a popover would be a window of its own. Delete is the system button with its title in red, since the red-tinted one is private to alerts, and as in macOS's alerts it isn't the default button, so Return can't delete. Esc cancels, and so does closing the popover. The ellipsis is for the question, as on Finder's Empty Trash…. Delete goes back to no countdown: the item reads `Set date` and the New Countdown form takes the popover's place, with one quiet line under its title, "Deleted “Going home”." and **Undo**, until the popover closes or a new countdown starts. Not "Cancel", which the form uses for discarding an edit.
- **Menu Bar ▸** the five styles, each showing what the item would read with it right now.
- **Background ▸** Liquid Glass or Solid. macOS 26 only.
- **Launch at Login**, checked once macOS confirms it, and mixed while it waits for approval. If macOS refuses a change or wants approval, one quiet line under the popover says so, with Try Again or Open Settings…; macOS's reason is its tooltip. While a change has failed, **Login Items Settings…** follows it here.
- **Notify Me**: the milestone notifications. See [Milestone notifications](#milestone-notifications).
- **About Days Until**: the standard About panel, where every Mac app keeps its version. It shows the icon, the name, "Version 0.4.2 (15)", the copyright and the licence. The popover closes first. Closing the panel, with ⌘W too, hands the keyboard back.
- **Updates ▸** under About, where every Mac app keeps Check for Updates…, so everything about updates is in one place. When Sparkle last looked, greyed out, sits above **Check for Updates…**, as Time Machine's menu shows its latest backup above Back Up Now, and Check for Updates… is greyed out while Sparkle is busy. Then, under a line, Install Automatically, Ask Before Installing or Don't Check. See [Keeping up to date](#keeping-up-to-date).
- **Quit Days Until** ⌘Q

⌘E and ⌘Q also work while the popover is open and the menu isn't.

### Background

On macOS 26 the popover is Liquid Glass by default, and Solid is one click away in the ••• menu, for people who find glass busy over a bright or detailed wallpaper. On macOS 13 to 15 there's no choice: the popover is always Solid. The setting is saved as `popoverBackground` and ignored before macOS 26, so upgrading later brings glass back as the default.

Only the popover's background changes, with its grouped boxes and fields. Menus, the menu bar, switches, buttons and the accent are drawn by macOS in the style of the system it runs on. Corner radii follow the system too: capsule fields and circular icon wells on macOS 26, smaller rounded rectangles before.

## Desktop widget

Small, Medium and Large widgets, for the desktop on macOS 14 and later. The visual design is the proposed revision in the Figma file [Days Until — Desktop Widgets](https://www.figma.com/design/Q48AfGQXmjmy0iy9I5OPV7).

- **A glance first.** A click anywhere on it opens the popover under the menu bar item, as a click on the item does. With no countdown, that's the New Countdown form.
- **The same rows in every state:** the icon and name, the readout, the runway, then one line in Small. Medium sets the day beside the readout, with the weekends left under it, and says what the runway shows under the runway, as the popover does. Large puts the day in full under the readout, then has the popover's runway with its month names, weeks, weekends and weekdays while counting, and, when a place is set, the arrival in "Your time" and the place's, each with its date and year. Without a place the line under the readout already says when.
- **The readout climbs the popover's ladder:** `75 days`; `5d 16h` in the final week, as in the menu bar, with the time beside the day; then the seconds clock in the accent, drawn by the system so it never goes stale, with "Until 9:40 AM tomorrow". On the day, `Today` in the accent and the popover's line, "Reached at 9:40 AM". After it, "Reached" and "Fri, Dec 18 · 3 days ago", never a negative count. With no countdown, the calendar icon, "Your next big day." and **Set date**, as in the menu bar.
- **Content:** a large count shrinks before its unit is cut short, and a long name truncates after one line.
- **The runway:** Large draws the popover's, and Medium the same without the month names it has no room for. Small has 2 pt ticks, all one height ahead, ending in a quiet dot. Both count in the finest unit that fits, as the popover's does.
- **On the desktop:** macOS draws the background, the shape and the one-colour desktop look; the widget has no card of its own. The icon, today's mark, the destination and the accent text are accentable, so tinted styles keep them apart from the rest. An emoji keeps its own colours.
- **Timeline:** an entry at each local midnight (or when the days drop, when the clocks have gone back), each hour of the final week as the readout's hours drop, each clock hour of the final 24 hours, the moment itself, and each midnight after it, up to 64 at a time. The app reloads it when the countdown changes, and when the clock, time zone or language does.
- **Sharing the countdown:** the widget runs in a sandbox of its own. The app copies the countdown to the preferences domain `com.yinfenglu.DaysUntil.shared`, through a temporary sandbox exception that lets the app write it and the widget read it. Not an app group: builds from source are ad hoc signed, with no team, and macOS asks the person for access to a group container that isn't their team's.
- **After an update:** the widget's process outlives the update, still running the old build, and macOS then turns down everything it draws ("Bundle version did not match"), leaving grey placeholders until the next login. So the widget reads its build when it starts, and quits when it's asked to draw and a different build is in its place; macOS starts the new one when it tries again. The app reloads the widget when it relaunches on the update, which asks it to draw.

## Milestone notifications

Five times along the way the app says how far there is to go, in the system's own notifications. The visual design is the Milestone notifications board in the Figma file.

- **Five fixed milestones, one switch.** 100 days, 30 days and a week to go, the day before, and the day. They come closer together as the day nears, and three land where the app already changes: hours join the menu bar in the final week, the seconds clock starts the day before, and the day is Today. There's nothing to choose between, so there's one switch, not a tick for each. Milestones of your own ("pack, 3 days before") would be reminders, which Reminders does better.
- **The switch:** "Notify me" in a new install's form, under "Launch at login" and ticked by default, and **Notify Me** in the ••• menu, under Launch at Login. The milestones are fixed, so the name stays short, and both have the tooltip "At 100, 30 and 7 days, the day before, and on the day". It's saved as `notifiesAtMilestones`, off until someone says yes, so a countdown from before the switch existed starts with it off. Like Launch at Login, the menu leaves it to the form's checkbox until a countdown starts.
- **Asked once, after a yes.** macOS asks for permission when Start Countdown is clicked with the box ticked, or when Notify Me is first turned on, never at launch. Don't Allow at its prompt turns the switch back off. macOS asks only once, so turning the switch on after that opens Days Until's page in System Settings › Notifications. While the switch is on and macOS has notifications off, the item shows a dash, as Launch at Login does while it waits for approval, and **Notification Settings…** follows it. A click on the dash turns the switch off. Permission is read again each time the popover opens and the app becomes active, so allowing them in System Settings takes effect then.
- **When:** the days before at 9:00 AM local time, the time Calendar alerts for an all-day event, on the day the count reaches 100, 30, 7 or 1, so they agree with the menu bar. The day itself at the moment for a timed countdown, as the item turns to Today, and at 9:00 AM for a date-only one, or at its moment if that's later, after travel. Only what's ahead: a countdown set 50 days out starts at 30.
- **What they say:** the countdown's name, then:
  - "100 days to go · Friday, December 18", the same at 30 days, and "A week to go · Friday, December 18", with the year when it isn't the year the notification arrives in.
  - "Tomorrow at 9:40 AM · 6:40 PM in Tokyo", the place's time taking its weekday when it's another day there, or "Tomorrow · Friday, December 18" for a date-only countdown still at midnight.
  - "Today’s the day."
- **A click opens the popover,** under the item, as a click on the widget does, and on the day with its confetti. No buttons and no badges; banner or alert, sound and Focus are the person's, in System Settings. The menu bar item never changes.
- **Scheduled with macOS:** one `UNNotificationRequest` per milestone, `milestone.100` to `milestone.0`, with a `UNCalendarNotificationTrigger` at its time in the Mac's zone, so they arrive whether or not the app is running. They're all replaced whenever the countdown, the switch, the clock, the time zone or the day changes, and on wake. Deleting the countdown removes them and Undo puts them back.
- **Never a wrong number.** A Mac that was asleep or off at 9:00 AM can be handed a milestone on a later day, when its number would be wrong, so the app takes back any that arrived on a day other than their own each time it reschedules.

## Keeping up to date

Sparkle keeps the app up to date, as quietly as the rest of it. The app never opens a window nobody asked for: anything it has to say waits in one line at the foot of the popover, which gets opened many times a day anyway, the way the launch at login line does. The menu bar item never changes for an update, since it belongs to the countdown, and there are no notifications or Dock badges. The visual design is the Updates board in the Figma file.

- **No question first.** Checking is on from the start. Sparkle would otherwise ask at the second launch, which for a menu bar app is usually at login: a window nobody asked for. Updates ▸ Don't Check turns it off.
- **Once a day,** in the background. Sparkle reads the feed and sends nothing but the request: no system profile.
- **Install Automatically**, the default: the update downloads by itself and must carry the release's EdDSA signature and the same Developer ID, or Sparkle throws it away. Days Until then relaunches on it the next time the display sleeps, out of sight, and the item is back in its place before anyone looks. Never while the popover is open, or while the form holds an edit, since the form keeps one while the popover is closed. Quitting installs it too. If the display hasn't slept for a week, Sparkle's own limit, the line offers it: "Version 0.3.0 is ready." with **Install and Relaunch** or **Later**. It offers it at once if Install Automatically is no longer the choice, since the app then won't install it by itself. Sparkle still installs it on quit, which can't be undone once downloaded.
- **Ask Before Installing:** the update waits in the line, "Version 0.3.0 is available.", with **Details**, which opens Sparkle's window after the popover closes, and **Later**. Nothing installs until Install Update in Sparkle's window. Sparkle's gentle reminders hand the scheduled alert to the app instead of showing it.
- **Later** hides the line at once and leaves the popover open. It comes back with the next daily check, as Remind Me Later does in Sparkle's window. Skip This Version there silences that version; Don't Check silences all of them.
- **After an update,** the first time the popover opens: "Updated to version 0.3.0." with **What's New**, which opens the release on GitHub. It goes when the popover closes.
- **Check for Updates…** closes the popover, and Sparkle checks and shows the update or "You're up to date!". An update already waiting to install is offered in the popover's line instead, with the popover left open, since Sparkle can't check while the app holds the install.
- **Sparkle's windows** are Sparkle's own, translated by Sparkle into the app's languages. They open on the screen where the popover was, since Sparkle on its own centres them on whichever display is the main one, which with two can be the other. While one is open, Days Until is in the Dock and ⌘-Tab, so it can't get lost behind other windows; it leaves them, and hands the keyboard back, when Sparkle's done.
- **Release notes:** the release's own bullets, without the install steps, embedded in the feed as Markdown.

## Edit form

The edit form replaces the popover's content rather than opening a separate window, because Settings windows in menu-bar-only apps have unreliable focus.

Closing the popover preserves an unsaved edit, including typed dates. Reopening resumes the form. Cancel explicitly discards the draft. On first launch the form also keeps what was typed.

Three groups, with no explanatory footnotes: labels, values and validation messages carry the meaning.

- **What:** the name, and the icon as one row of wells: the preset symbols, then a well that opens our own emoji picker inside the group, under the wells.
- **When:** the date, then optional fields as switches that reveal their value in place. **Exact time** shows a time field beside its switch, with our own hours and minutes under it on a click (see below). **Second time zone** shows a search inside the group, with each result's time now. Once a place is picked, the field shows it with the moment there ("Thu 06:00"), and searches again from its name while it has focus. Return picks the highlighted result and never saves the form; Escape or leaving the field keeps the place. The place never defines the input zone. A date-only target that is no longer midnight after travel gets one line under the group: "Counts down to 17:00 your time."
- **Progress:** Counting from.

Dates open our own calendar inside the group, under the field. SwiftUI's graphical date picker can't be styled, disable single days or say what a choice means, so the form uses its own, drawn like the system's:

- **Six weeks, always,** so paging months never moves the rows below.
- **Only valid days.** A timed countdown allows choosing any day that has not ended, so a DST gap can be corrected in the time field. A date-only countdown requires its start of day to be in the future. Counting from must precede the target instant; the same day is allowed when its start precedes the exact target time.
- **Today's number** takes the accent colour, and the chosen day is a filled accent circle. Weekends are secondary.
- **It says what the choice means:** "Friday, December 18 · in 80 days", or "Monday, August 3 · 137 days before".
- **Keyboard:** the arrow keys move by day and week, Page Up and Page Down by month, T jumps to today, Return picks and Esc closes. The field accepts complete localized dates with a year or ISO dates (`2027-12-19`). Return or leaving the field commits valid input; clicking Save also reads pending text. Invalid text remains visible with an error and disables Save. Esc explicitly cancels pending text.
- **Localised:** the week starts on the locale's first weekday, and the names come from the system. The grid stays Gregorian to match the stored input components; neutral UTC picker values prevent DST normalization.

Times are typed in the system's own time field, in the Mac's format, as before. A click on the field or on its clock also opens our own hours and minutes inside the group, under the field, so a time can be set without the keyboard. Tabbing into the field doesn't open them, and neither does turning Exact time on, so typing never meets them:

- **An hour, then a minute,** drawn like the calendar: rows of six, the chosen one a filled accent circle, hover a quiet well. The field follows each click, and typing in the field moves the choice. Choosing a minute closes them, as choosing a day closes the calendar.
- **Every five minutes.** Any other minute is typed, and then none is filled.
- **The Mac's own clock:** 12- or 24-hour as System Settings says, with the hours numbered as the field writes them: 12, 1 … 11, 0 … 11 for Japanese on a 12-hour clock, or 00 … 23. On a 12-hour clock AM and PM are the system's segmented control, and switching keeps the hour.
- **Closing:** the chevron that replaces the clock, Return or Esc (which then never save or cancel the form), another field taking focus, or turning Exact time off. The calendar and the hours and minutes are never open together.

The emoji picker is our own because the system's can't be used from the popover. Opened at a text caret, Apple's picker takes activation when clicked, and after the pick hands it, with the emoji, to the last regular app, skipping a menu bar app. So the emoji never arrived and was typed into whatever app was in front before. Ours:

- **Every emoji Unicode lists,** in the categories and order of Apple's picker, without skin tone variants. The list is `DaysUntil/Resources/Emoji.tsv`, built by `scripts/make-emoji-list.py` from Unicode's `emoji-test.txt` and CLDR's English annotations. Emoji newer than the Mac, which Apple Color Emoji can't draw as one, are dropped when the list loads.
- **Search** by name and keyword ("home" finds 🏠), whole words before prefixes, single emoji before sequences.
- **A bar** under the grid jumps to each category.
- **Keyboard:** typing searches, the arrow keys move through the emoji, Return picks, and Esc clears the search, then closes. Picking an emoji, a preset symbol, or another field closes it.

On first launch the popover opens by itself, titled "New Countdown", with the name focused. The date is a month out, counting from today. The form also offers "Launch at login" and "Notify me", both on by default, Quit, and "Start Countdown", which enables once there's a name. The ••• button sits beside the title, so the settings, About, and Updates ▸ are there before any countdown is; Edit Countdown… and Delete Countdown… are greyed out, and Launch at Login and Notify Me are left to the form's checkboxes.

After the countdown is deleted, the form is the same without its two checkboxes, which the ••• menu has by then, and the app doesn't open it by itself at launch: the menu bar item's `Set date` asks instead. Whether a countdown has ever been started is saved as `isSetUp`.

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
- **The popover's window:** a borderless, non-activating panel, as NSPopover's own window is, so it takes the keyboard as the key window whether or not the window server lets the app activate. It sits at the level of the system's menu bar menus, just under the menu bar. Its content view clips to the rounded corners. On macOS 26 an `NSGlassEffectView` lies under the content, as in NSPopover, and the Solid panel is a SwiftUI background over it; before macOS 26 there's no glass. The window takes the content's size as soon as the content has laid out, keeping its top edge in place. The content's size constraints alone left it a layout pass behind on screen, with the content drawn centred in the old frame: a few frames as it grew, and as it shrank, until the countdown next ticked. Esc reaches the panel as `cancelOperation(_:)` unless a Cancel button or a field takes it first.
- **Keyboard in the form:** macOS 13 has no `onKeyPress`, so the calendar and the place search read keys with a local event monitor while they're on screen.
- **Minimum macOS: 13 Ventura.**
  - `SMAppService` (launch at login) needs 13, and so does `NSHostingController` resizing the popover to fit its content.
  - `@Observable` needs 14, so state uses `ObservableObject` instead.
  - The desktop widget needs 14, the first with widgets on the desktop. On 13 the app runs without it.
  - The current Xcode can't target anything below macOS 12. Supporting 12 would need a separate login-item helper, only to add 2015–2016 Macs, so it isn't worth it.
- **Storage:** `UserDefaults`, with the countdown encoded as JSON under one key and display settings stored alongside. A copy of the countdown goes to the widget; see [Desktop widget](#desktop-widget).
- **Launch at login:** `SMAppService.mainApp`.
- **Notifications:** `UNUserNotificationCenter`, asking for alerts and sounds; the sandbox needs nothing more. `MilestoneNotifications` is the app's side and knows nothing of UserNotifications, so it's tested with a stand-in; `SystemNotifications` is the bridge and the notification center's delegate, made as the app starts launching so a click that launches it still opens the popover. The test host never makes one, since it would make macOS ask the person.
- **Updates:** [Sparkle](https://sparkle-project.org) 2's `SPUStandardUpdaterController`, with its gentle reminders (`SPUStandardUserDriverDelegate`) handing scheduled alerts to the popover's line, and `updater(_:willInstallUpdateOnQuit:immediateInstallationBlock:)` holding a downloaded update for the next display sleep. `Updates` is the app's side and knows nothing of Sparkle, so it's tested with a stand-in; `SparkleUpdater` is the bridge. The sandbox stays: Sparkle installs through its Installer XPC service and downloads through its Downloader service (`SUEnableInstallerLauncherService`, `SUEnableDownloaderService`), so the app itself still asks for no network access, with two mach-lookup exceptions, `…-spks` and `…-spki`. The feed is `appcast.xml`, uploaded with each GitHub release and read from `releases/latest/download/appcast.xml`, so it always names the latest; `scripts/make-appcast.py` writes it and signs the zip with the EdDSA key in the login keychain, whose public half is `SUPublicEDKey` in `Info.plist`. Xcode leaves Sparkle's helpers ad hoc signed, which notarization rejects, so `scripts/sign-sparkle.sh` signs them with the app's identity before notarizing. The app's file is `Days Until.app`, so Finder and Spotlight show the name as it's written, and so do the menu bar while Sparkle's windows have the app in the Dock; its executable and Swift module stay `DaysUntil`. Sparkle installs an update over the copy where it is, keeping its file name, so a copy installed as `DaysUntil.app` before the rename keeps that name; it finds the renamed app in the zip by its bundle identifier. Tests never start Sparkle.
- **Distribution:** each release has a disk image for people, `DaysUntil-<version>.dmg`, beside the zip Sparkle updates from. Opening it shows the app, an arrow and the Applications folder, so installing is one drag. `scripts/make-dmg.py` builds it with [dmgbuild](https://github.com/dmgbuild/dmgbuild), which writes the window's layout into the image's `.DS_Store` without driving Finder, and draws the background at 1x and 2x. The background is white, since Finder shows any window with a background picture in light mode, with black labels. The image is HFS+, which Finder's background pictures were made for, and is signed, notarized and stapled like the app inside it.
- **Project:** a plain Xcode project, committed to git. It uses folder-synchronized groups (Xcode 16+), so adding or removing source files doesn't change the project file. The widget also builds `Countdown`, `CountdownMath`, `NumberPhrase`, `Theme` and the string catalog from the app's folder, listed in the project file. No project generator is needed; Sparkle, the only dependency, comes in through Swift Package Manager.

### Structure

```
DaysUntil/
  App/        app entry, status item and popover, the ••• menu, menu bar clock, updates and Sparkle,
              milestone notifications
  Model/      Countdown (data), CountdownMath (pure calculations), Draft, DateEntry, Store (persistence)
  Views/      MenuBarLabel, PopoverView, CountdownView, RunwayView, ConfettiView, EditView,
              CalendarField, PlacePicker, FormControls, Theme (colour tokens and radii)
DaysUntilWidget/  the desktop widget: its provider, views and runway
DaysUntilTests/
DaysUntilWidgetTests/  builds the widget's code and the model it shares, since the extension can't be loaded
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
- **The popover's readout and runway:** the precision ladder, the finest unit that fits, and ticks per day, week, month, year and hour.
- **The widget's timeline:** an entry for every change of readout and runway day, across daylight saving too.
- **The widget:** its timeline from the shared countdown, what each size says at each step, every size and runway drawn, and telling when an update has replaced it.
- **The keyboard:** the calendar, the emoji picker, the place search, and typing in the time field with its hours and minutes open, with real key events in windows off screen that never become key. Keys that would only beep are left out, so the tests stay silent.
- **The views:** each drawn off screen at every step, checking what shows when, such as the arrival box, the other units and the confetti's fade. Return saves the form and Esc cancels it, through their keyboard shortcuts.
- **The menu bar and the ••• menu:** the item's title, spacing and tint, its clock's timer, and each menu action except Quit.
- **Milestones:** when each arrives and what it says, the count agreeing with each across daylight saving, only what's ahead, asking once and only after a yes, Don't Allow, the dash and System Settings, the schedule following the countdown through delete and undo, and taking back one delivered late.
- **Updates:** the three choices as Sparkle's two settings, each line and when it shows, Later until the next day, the install held for a display sleep and never with the popover open or an edit in the form, the week-old update offered, and "Updated to" once.

The status item's popover window, opening, placing and fading under the menu bar, is left to trying it by hand, since testing it would put windows on the screen.

## Later

These are out of scope for the first version:

- **More than one countdown,** with one pinned to the menu bar.
- **A name of your own for the place,** e.g. `Asia/Shanghai` called "Home". The place's field used to double as its name, so it looked like a search but took any text; it's now only a search, and the place is shown by its city. A name would need a control of its own, apart from the search. Places saved with a name before keep it.
