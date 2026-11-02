// 課表資料: ~/Library/Application Support/NotchSchedule/schedule.json
import SwiftUI

// day: 1=一 ... 5=五；url 可選，點卡片會打開（例如 Canvas 課程頁）
struct C: Codable { let day: Int; let start, end, code, name, type, room: String; var url: String? = nil }

struct SFile: Codable {
    var colors: [String: String]
    var classes: [C]
    var termStart: String? = nil       // "2026-08-24"：這天之前不顯示課
    var termEnd: String? = nil         // "2026-12-16"：這天之後不顯示課
    var skip: [String]? = nil          // 放假日，例如 ["2026-11-26", "2026-11-27"]
}

let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("NotchSchedule")
let sfile = dir.appendingPathComponent("schedule.json")

// 第一次啟動時寫入的範例
let sample = SFile(colors: ["PHYS 1001": "#E0E680", "MATH 1271": "#ADD9E6"], classes: [
    C(day: 1, start: "09:05", end: "09:55", code: "PHYS 1001", name: "Intro Physics", type: "Lecture", room: "Tate Hall 105"),
    C(day: 3, start: "09:05", end: "09:55", code: "PHYS 1001", name: "Intro Physics", type: "Lecture", room: "Tate Hall 105"),
    C(day: 2, start: "13:25", end: "14:15", code: "MATH 1271", name: "Calculus I", type: "Lecture", room: "Vincent Hall 16"),
])

// 回傳 (課表, 檔案格式是否錯誤)
func loadSched() -> (SFile, Bool) {
    let fm = FileManager.default
    if !fm.fileExists(atPath: sfile.path) {
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? e.encode(sample).write(to: sfile)
        return (sample, false)
    }
    guard let d = try? Data(contentsOf: sfile), let s = try? JSONDecoder().decode(SFile.self, from: d)
    else { return (sample, true) }
    return (s, false)
}

func mins(_ s: String) -> Int { (Int(s.prefix(2)) ?? 0) * 60 + (Int(s.suffix(2)) ?? 0) }

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: .whitespaces); if h.hasPrefix("#") { h.removeFirst() }
        let v = UInt64(h, radix: 16) ?? 0x999999
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
