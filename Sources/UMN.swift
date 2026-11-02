// 從 UMN 官方行事曆 (asr.umn.edu) 抓開學日、最後上課日、假日
import Foundation

struct UMNTerm {
    let name: String
    let start, end: Date
    let holidays: [Date]
    let src: URL
}

struct FetchErr: LocalizedError { let errorDescription: String? }

enum UMN {
    static let months = ["january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7,
                         "august": 8, "september": 9, "october": 10, "november": 11, "december": 12]

    // 例: https://asr.umn.edu/2026-27-twin-cities-and-rochester-calendar
    static func url(_ fy: Int) -> URL {
        URL(string: "https://asr.umn.edu/\(fy)-\(String(format: "%02d", (fy + 1) % 100))-twin-cities-and-rochester-calendar")!
    }

    static func fetch(now: Date = Date()) async throws -> UMNTerm {
        let cl = Calendar.current
        let y = cl.component(.year, from: now), mo = cl.component(.month, from: now)
        let fy = mo >= 6 ? y : y - 1                              // 學年從秋季開始
        let u = url(fy)
        var req = URLRequest(url: u); req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let html = String(data: data, encoding: .utf8) else {
            throw FetchErr(errorDescription: "學校還沒公布 \(fy)-\(fy + 1) 的行事曆，或網址改了")
        }

        // 每個學期: 開學、最後上課日、放假
        var start: [String: Date] = [:], end: [String: Date] = [:], brk: [String: [Date]] = [:]
        var sec = "", sy = 0
        for l in lines(html) {
            if let r = l.range(of: #"(Fall|Spring) Semester (\d{4})"#, options: .regularExpression) {
                let h = String(l[r]); sec = h.hasPrefix("Fall") ? "Fall" : "Spring"; sy = Int(h.suffix(4)) ?? y
                continue
            }
            if !l.contains("\t") && l.range(of: "Session", options: .caseInsensitive) != nil { sec = ""; continue }
            let c = l.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !sec.isEmpty, c.count >= 2 else { continue }
            let ev = c[c.count - 1].lowercased(), ds = days(c[0], sy)
            guard !ds.isEmpty else { continue }
            if ev.contains("classes begin") { start[sec] = ds[0] }
            else if ev.contains("last day of instruction") { end[sec] = ds[0] }
            else if ev.contains("break") || ev.contains("holiday") || ev.contains("no class") { brk[sec, default: []] += ds }
        }

        let today = cl.startOfDay(for: now)
        let pick: String
        if let fe = end["Fall"], today <= fe { pick = "Fall" } else { pick = "Spring" }
        guard let a = start[pick], let b = end[pick] else {
            throw FetchErr(errorDescription: "找不到日期，學校網頁格式可能改了")
        }
        var hol = brk[pick] ?? []
        if pick == "Fall" { hol += thanksgiving(cl.component(.year, from: a)) }   // 感恩節: 11 月第 4 個週四 + 週五
        hol = Array(Set(hol.map { cl.startOfDay(for: $0) })).filter { $0 >= a && $0 <= b }.sorted()
        return UMNTerm(name: "\(pick) \(cl.component(.year, from: a))", start: a, end: b, holidays: hol, src: u)
    }

    // HTML -> 一行一列，欄位用 tab 分開
    static func lines(_ html: String) -> [String] {
        var s = html.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        for (a, b) in [("</tr>", "\n"), ("</h2>", "\n"), ("</h3>", "\n"), ("</td>", "\t"), ("</th>", "\t")] {
            s = s.replacingOccurrences(of: a, with: b, options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        return s.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // "September 8" / "December 17-19, 21-23" / "March 9-13" -> 日期們
    static func days(_ s: String, _ y: Int) -> [Date] {
        var m = 0, out: [Date] = []
        for w in s.split(whereSeparator: { $0 == " " || $0 == "," }) {
            let k = w.lowercased().trimmingCharacters(in: .punctuationCharacters.subtracting(CharacterSet(charactersIn: "-")))
            if let mm = months[k] { m = mm; continue }
            let n = k.split(separator: "-").compactMap { Int($0) }
            guard m > 0, let a = n.first, a <= 31 else { continue }
            let b = n.count > 1 ? n[1] : a
            for d in a...max(a, b) {
                if let dt = Calendar.current.date(from: DateComponents(year: y, month: m, day: d)) { out.append(dt) }
            }
        }
        return out
    }

    static func thanksgiving(_ y: Int) -> [Date] {
        let cl = Calendar.current
        guard let th = cl.date(from: DateComponents(year: y, month: 11, weekday: 5, weekdayOrdinal: 4)),
              let fr = cl.date(byAdding: .day, value: 1, to: th) else { return [] }
        return [th, fr]
    }
}
