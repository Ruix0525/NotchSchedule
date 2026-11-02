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
Gear button → 編輯課表… (`~/Library/Application Support/NotchSchedule/schedule.json`)

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
System Settings → Internet Accounts → add Google, enable Calendars. Then gear → 顯示行事曆事件.
