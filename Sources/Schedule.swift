// 課表檔案: ~/Library/Application Support/NotchSchedule/schedule.json (設定視窗會自動讀寫)
import SwiftUI
import AppKit

// day: 1=一 ... 5=五, 6=六, 7=日
struct C: Codable { let day: Int; let start, end, code, name, type, room: String; var url: String? = nil }

struct SFile: Codable {
    var colors: [String: String]
    var classes: [C]
    var termStart: String? = nil
    var termEnd: String? = nil
    var skip: [String]? = nil
}

let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("NotchSchedule")
let sfile = dir.appendingPathComponent("schedule.json")

let sample = SFile(colors: ["PHYS 1001": "#E0E680", "MATH 1271": "#ADD9E6"], classes: [
    C(day: 1, start: "09:05", end: "09:55", code: "PHYS 1001", name: "Intro Physics", type: "Lecture", room: "Tate Hall 105"),
    C(day: 3, start: "09:05", end: "09:55", code: "PHYS 1001", name: "Intro Physics", type: "Lecture", room: "Tate Hall 105"),
    C(day: 2, start: "13:25", end: "14:15", code: "MATH 1271", name: "Calculus I", type: "Lecture", room: "Vincent Hall 16"),
])

func writeSched(_ s: SFile) {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    try? e.encode(s).write(to: sfile, options: .atomic)
}

// 回傳 (課表, 檔案格式是否錯誤)
func loadSched() -> (SFile, Bool) {
    if !FileManager.default.fileExists(atPath: sfile.path) { writeSched(sample); return (sample, false) }
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
    var hex: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#C8C8C8" }
        return String(format: "#%02X%02X%02X", Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()), Int((c.blueComponent * 255).rounded()))
    }
}
