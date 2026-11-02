#!/bin/bash
# 套用「下載項目」裡最新下載的 NotchSchedule 壓縮檔 (不管叫 (1) (2) 都會抓最新的)
# 用法: ./upgrade.sh         更新 + 安裝
#       ./upgrade.sh push    更新 + 安裝 + 上傳 GitHub
set -e
REPO="$HOME/NotchSchedule"
DL="$HOME/Downloads"

ZIP=$(ls -t "$DL"/NotchSchedule*.zip 2>/dev/null | head -1)
if [ -z "$ZIP" ]; then echo "❌ 下載項目裡找不到 NotchSchedule 壓縮檔"; exit 1; fi
echo "📦 使用：$(basename "$ZIP")"

TMP=$(mktemp -d)
ditto -x -k "$ZIP" "$TMP"
SRC="$TMP/NotchSchedule"; [ -d "$SRC" ] || SRC="$TMP"
# 合併進專案 (保留 .git 和你的個人課表)
rsync -a --exclude .git --exclude schedule.json "$SRC/" "$REPO/"
rm -rf "$TMP"

# 清掉下載項目裡的舊壓縮檔和解壓縮資料夾
rm -f "$DL"/NotchSchedule*.zip
rm -rf "$DL/NotchSchedule" "$DL"/"NotchSchedule "[0-9]*
echo "🧹 已清理下載項目"

cd "$REPO"
./build.sh install

if [ "$1" == "push" ]; then
    V=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
    git add .
    git commit -m "v$V" || echo "（沒有新變更）"
    git push
    echo "☁️ 已上傳 GitHub：v$V"
    # 新版本 -> 打 tag，GitHub 會自動打包發佈到 Releases (朋友從連結下載)
    if ! git rev-parse "v$V" >/dev/null 2>&1; then
        git tag "v$V" && git push origin "v$V"
        echo "🚀 已發佈 v$V，幾分鐘後朋友就能從 Releases 下載"
    fi
fi
