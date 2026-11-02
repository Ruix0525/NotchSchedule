// 匯入課表: 讓朋友用 AI 把課表截圖轉成 JSON，再貼進來
import SwiftUI
import AppKit
import UniformTypeIdentifiers

let aiPrompt = """
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
"""

// 寬鬆讀取: AI 漏掉某些欄位也能匯入
struct ImpClass: Codable {
    var day: Int
    var start, end: String
    var code: String
    var name: String?
    var type: String?
    var room: String?
    var url: String?
}
struct ImpFile: Codable { var colors: [String: String]?; var classes: [ImpClass] }

enum Importer {
    // 回傳 (課表, 錯誤訊息)
    static func parse(_ raw: String) -> (SFile?, String?) {
        guard let a = raw.firstIndex(of: "{"), let b = raw.lastIndex(of: "}") else {
            return (nil, "找不到 JSON。請確認你複製的是 AI 給的 JSON（{ 開頭、} 結尾）。")
        }
        let txt = String(raw[a...b])
            .replacingOccurrences(of: "“", with: "\"").replacingOccurrences(of: "”", with: "\"")
        guard let d = txt.data(using: .utf8) else { return (nil, "文字編碼有問題") }
        let f: ImpFile
        do { f = try JSONDecoder().decode(ImpFile.self, from: d) }
        catch { return (nil, "JSON 格式不對：\(error.localizedDescription)\n把這段錯誤訊息貼回給 AI，請它修正。") }

        var cls: [C] = [], bad: [String] = []
        let ok = try! NSRegularExpression(pattern: #"^\d{1,2}:\d{2}$"#)
        func fix(_ t: String) -> String { t.count == 4 ? "0" + t : t }          // 9:05 -> 09:05
        for x in f.classes {
            let s = fix(x.start), e = fix(x.end)
            let valid = (1...7).contains(x.day)
                && ok.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
                && ok.firstMatch(in: e, range: NSRange(e.startIndex..., in: e)) != nil
                && s < e && !x.code.isEmpty
            if !valid { bad.append("\(x.code) day \(x.day) \(x.start)-\(x.end)"); continue }
            cls.append(C(day: x.day, start: s, end: e, code: x.code, name: x.name ?? "", type: x.type ?? "Lecture",
                         room: x.room ?? "TBA", url: x.url))
        }
        if cls.isEmpty { return (nil, "沒有可以匯入的課。" + (bad.isEmpty ? "" : "\n有問題的：" + bad.joined(separator: "、"))) }
        // 沒給顏色的課自動配色
        var cols = f.colors ?? [:]
        for (i, code) in Array(Set(cls.map(\.code))).sorted().enumerated() where cols[code] == nil {
            cols[code] = palette[i % palette.count]
        }
        return (SFile(colors: cols, classes: cls), bad.isEmpty ? nil : "以下 \(bad.count) 筆格式不對，已略過：" + bad.joined(separator: "、"))
    }

    // 寫入: replace = 取代，不然就是加進去
    static func apply(_ f: SFile, replace: Bool) {
        var (sf, broken) = loadSched()
        if broken || replace { sf.classes = []; if broken { sf.colors = [:] } }
        sf.classes += f.classes
        for (k, v) in f.colors { sf.colors[k] = v }
        writeSched(sf)
    }
}

// 課表分頁底下的「匯入」選單
struct ImportMenu: View {
    @ObservedObject var s: Store
    @State var pending: SFile?
    @State var warn: String?
    @State var note: String?

    func handle(_ text: String) {
        let (f, e) = Importer.parse(text)
        if let f { pending = f; warn = e } else { note = e }
    }

    var body: some View {
        Menu {
            Button("① 複製給 AI 的指令") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(aiPrompt, forType: .string)
                note = "已複製！\n貼到 ChatGPT / Claude / Gemini，附上你的課表截圖（例如 MyU 的課表），把它回給你的 JSON 整段複製起來，再回來按「② 從剪貼簿匯入」。"
            }
            Button("② 從剪貼簿匯入") { handle(NSPasteboard.general.string(forType: .string) ?? "") }
            Button("選擇 JSON 檔案…") {
                let p = NSOpenPanel(); p.allowedContentTypes = [.json, .plainText]; p.allowsMultipleSelection = false
                NSApp.activate(ignoringOtherApps: true)
                if p.runModal() == .OK, let u = p.url, let t = try? String(contentsOf: u, encoding: .utf8) { handle(t) }
            }
        } label: { Label("匯入", systemImage: "square.and.arrow.down") }
        .menuStyle(.borderlessButton).fixedSize()
        .confirmationDialog("找到 \(Set(pending?.classes.map(\.code) ?? []).count) 門課、\(pending?.classes.count ?? 0) 個上課時段",
                            isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("取代目前的課表", role: .destructive) { if let f = pending { Importer.apply(f, replace: true); s.load() }; pending = nil }
            Button("加到目前的課表") { if let f = pending { Importer.apply(f, replace: false); s.load() }; pending = nil }
            Button("取消", role: .cancel) { pending = nil }
        } message: { Text(warn ?? "要取代還是加到現在的課表？") }
        .alert(note ?? "", isPresented: Binding(get: { note != nil }, set: { if !$0 { note = nil } })) {
            Button("好") { note = nil }
        }
    }
}
