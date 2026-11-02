# NotchSchedule

Hover over your MacBook's notch to see your weekly class schedule.
滑鼠移到 MacBook 瀏海，就會從瀏海長出整週課表。

## Features
- Panel morphs out of the notch; weekly Mon–Fri view (card list or timeline with a "now" line)
- "Next class in…" / "In class — X min left" banner
- Notch live countdown: the notch widens to show the class and minutes left, 15 min before and during class
- Reminder before class: auto pop-up and/or macOS notification (5/10/15/30 min)
- Events from macOS Calendar, including Google Calendar accounts
- Term dates and holidays (`termStart`, `termEnd`, `skip`), per-class links (`url`)
- Settings window: visual course editor (days, times, colors, rooms, links), term dates & holidays, calendar picker
- Google Calendar via macOS Internet Accounts: all calendars, colors, all-day events, weekends, event details
- Hide individual events or all events with the same title (restore in Settings)
- Light / dark / auto theme with accent colors; week navigation
- UMN Twin Cities school calendar (term dates, finals, university holidays) auto-updated weekly from asr.umn.edu and hr.umn.edu; holidays hide classes automatically
- "Now" indicator on the timeline and in the card list
- Preview buttons for the notch countdown and reminders
- Interactive onboarding tour with spotlight (replay in Settings → 一般)
- Menu bar icon + gear button, launch at login

## Requirements
- macOS 14 Sonoma or later
- Xcode Command Line Tools (`xcode-select --install`)

## Build & install
```bash
./build.sh install      # build + install to /Applications
./build.sh dist         # universal build zipped for sharing
./update.sh             # git pull + reinstall
```

## Schedule format
Use the Settings window (gear → 設定…). Advanced: the data lives in `~/Library/Application Support/NotchSchedule/schedule.json`

```json
{
  "termEnd": "2026-12-16",
  "skip": ["2026-11-26", "2026-11-27"],
  "colors": { "PHYS 2201": "#E0E680" },
  "classes": [
    { "day": 1, "start": "09:05", "end": "09:55", "code": "PHYS 2201",
      "name": "Thermo & Stat Phys", "type": "Lecture", "room": "Tate Hall 105",
      "url": "https://canvas.umn.edu/" }
  ]
}
```
`day`: 1 = Mon … 5 = Fri, times in 24h `HH:mm`. `url` is optional. Changes apply within 30 s.

## Google Calendar
System Settings → Internet Accounts → add Google, enable Calendars. Then gear → 設定… → 行事曆, and pick which calendars to show.
