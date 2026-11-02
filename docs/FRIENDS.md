# 給朋友：安裝與匯入課表

## 安裝（不用碰程式碼）

1. 下載最新版：**[NotchSchedule.zip](https://github.com/Ruix0525/NotchSchedule/releases/latest/download/NotchSchedule.zip)**，解壓縮後把 **NotchSchedule.app** 拖進「應用程式」資料夾。
2. 打開「終端機」，貼上這行再按 Enter（因為 App 沒有 Apple 付費簽章，第一次要解除隔離）：

   ```
   xattr -dr com.apple.quarantine /Applications/NotchSchedule.app
   ```

3. 打開 NotchSchedule，會自動跑新手教學。需要 macOS 14 以上、有瀏海的 MacBook 效果最好。

## 匯入你的課表（讓 AI 幫你）

1. 滑鼠移到瀏海 → 齒輪 → 設定… → 「課表」分頁，左下角點 **匯入 → ① 複製給 AI 的指令**。
2. 打開 ChatGPT / Claude / Gemini，貼上指令，再附上你的課表截圖（MyU 的課表頁最好）。
3. 把 AI 回給你的 JSON **整段複製**。
4. 回到設定，點 **匯入 → ② 從剪貼簿匯入**，選「取代目前的課表」。

匯入後可以直接在設定裡改顏色、時間、教室。

## 更新

不用管它：App 每 6 小時會自動檢查，有新版就在你沒在用的時候自動下載、安裝、重新打開，完成後會跳通知。
想手動更新：齒輪 → 檢查更新。不想自動裝：設定 → 一般 → 更新。課表和設定都不會不見。

## Google 行事曆

系統設定 → 網際網路帳號 → 登入 Google 並打開「行事曆」，再到 NotchSchedule 設定 → 行事曆 勾選要顯示的日曆。

## 給 AI 的指令（跟 App 裡複製的一樣）

請幫我把附上的課表（截圖或文字）轉成下面這個 JSON 格式，給 Mac 的 NotchSchedule 使用。

規則：
1. 只輸出一個 JSON，放在 ```json 程式碼區塊裡，前後不要有任何說明文字。
2. classes 裡「每一堂課的每一個上課日」都是一筆。例如週一三五都有 Lecture，就要寫三筆。
3. day：1=週一、2=週二、3=週三、4=週四、5=週五、6=週六、7=週日。
4. start / end：24 小時制，固定兩位數，例如 "09:05"、"15:35"。
5. code：課號，例如 "PHYS 2201"、"CSCI 1133"。同一門課的 code 必須完全一樣。
6. name：短一點的課名（20 個字元以內），例如 "Thermo & Stat Phys"。
7. type：Lecture、Discussion、Laboratory、Recitation、Seminar 其中一個。
8. room：教室，大樓名稱可以縮寫，例如 "Tate Hall 105"。沒有教室就寫 "TBA"。
9. colors：每一門課（每個 code）給一個淺色系的 HEX 顏色，不同課顏色要不同，例如 "#E0E680"、"#ADD9E6"、"#F4B6C2"、"#C3B1E1"、"#B5EAD7"、"#EDCC73"。
10. 沒有固定時間的課（線上非同步、TBA）不要放進去。

格式範例：
```json
{
  "colors": { "PHYS 2201": "#E0E680", "CSCI 1133": "#DED4AB" },
  "classes": [
    { "day": 1, "start": "09:05", "end": "09:55", "code": "PHYS 2201", "name": "Thermo & Stat Phys", "type": "Lecture", "room": "Tate Hall 105" },
    { "day": 4, "start": "08:00", "end": "09:55", "code": "CSCI 1133", "name": "Intro to Programming", "type": "Laboratory", "room": "Keller Hall 1-250" }
  ]
}
```
