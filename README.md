# NotchSchedule

Hover over your MacBook's notch to see your weekly class schedule.
滑鼠移到 MacBook 瀏海，就會彈出整週課表。

## Features
- Weekly Mon–Fri view with color-coded course cards
- "Next class in…" / "In class — X min left" banner
- Reminder before class: auto pop-up and/or macOS notification (5/10/15/30 min)
- Shows events from macOS Calendar, including Google Calendar accounts added in System Settings
- Menu bar icon, launch at login

## Requirements
- macOS 14 Sonoma or later, Apple Silicon
- Xcode Command Line Tools (`xcode-select --install`)

## Build & install
```bash
./build.sh install
```

## Edit your schedule
Menu bar icon → 編輯課表… (opens `~/Library/Application Support/NotchSchedule/schedule.json`).
`day`: 1 = Mon … 5 = Fri, times in 24h `HH:mm`. Changes apply within 30 s.

## Google Calendar
System Settings → Internet Accounts → add your Google account and enable Calendars.
Then menu bar icon → 顯示行事曆事件.
