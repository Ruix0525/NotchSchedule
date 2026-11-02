#!/bin/bash
# 用法: ./build.sh          只建置到 build/
#       ./build.sh install  建置並安裝到「應用程式」，然後啟動
set -e
cd "$(dirname "$0")"
APP=build/NotchSchedule.app
SUP="$HOME/Library/Application Support/NotchSchedule"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
echo "⏳ 編譯中..."
swiftc -parse-as-library -O -target arm64-apple-macos14.0 Sources/*.swift -o "$APP/Contents/MacOS/NotchSchedule"
codesign --force --sign - "$APP"
echo "✅ 建置完成：$APP"

if [ "$1" == "install" ]; then
    # 有個人課表且還沒安裝過 -> 複製過去 (不會覆蓋你之後改過的)
    if [ -f schedule.json ] && [ ! -f "$SUP/schedule.json" ]; then
        mkdir -p "$SUP" && cp schedule.json "$SUP/"
        echo "📅 已匯入 schedule.json"
    fi
    pkill -x NotchSchedule || true
    rm -rf /Applications/NotchSchedule.app
    cp -R "$APP" /Applications/
    open /Applications/NotchSchedule.app
    echo "✅ 已安裝到「應用程式」並啟動"
fi
