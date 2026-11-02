// 課表資料: 從 ~/Library/Application Support/NotchSchedule/schedule.json 讀取
import SwiftUI

struct C: Codable { let day: Int; let start, end, code, name, type, room: String }  // day: 1=一 ... 5=五
struct SFile: Codable { var colors: [String: String]; var classes: [C] }

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
