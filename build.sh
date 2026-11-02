#!/bin/bash
# 用法: ./build.sh          建置 (Apple Silicon) 到 build/
#       ./build.sh install  建置並安裝到「應用程式」，然後啟動
#       ./build.sh dist     建置通用版 (M 系列 + Intel) 並壓縮成 build/NotchSchedule.zip，給朋友或 Releases 用
set -e
cd "$(dirname "$0")"
APP=build/NotchSchedule.app
BIN="$APP/Contents/MacOS/NotchSchedule"
SUP="$HOME/Library/Application Support/NotchSchedule"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
echo "⏳ 編譯中..."
if [ "$1" == "dist" ]; then
    swiftc -parse-as-library -O -target arm64-apple-macos14.0  Sources/*.swift -o build/ns-arm64
    swiftc -parse-as-library -O -target x86_64-apple-macos14.0 Sources/*.swift -o build/ns-x86_64
    lipo -create build/ns-arm64 build/ns-x86_64 -output "$BIN"
    rm build/ns-arm64 build/ns-x86_64
else
    swiftc -parse-as-library -O -target arm64-apple-macos14.0 Sources/*.swift -o "$BIN"
fi
codesign --force --sign - "$APP"
echo "✅ 建置完成：$APP"

if [ "$1" == "dist" ]; then
    rm -f build/NotchSchedule.zip
    (cd build && ditto -c -k --keepParent NotchSchedule.app NotchSchedule.zip)
    echo "📦 已打包：build/NotchSchedule.zip"
fi

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
