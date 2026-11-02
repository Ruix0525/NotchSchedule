// 從 UMN 官方網站抓: 學期日期 (asr.umn.edu) + 大學假日 (hr.umn.edu, Twin Cities)
import Foundation

struct UMNTerm {
    let name: String
    let start, end: Date
    let src: URL
}
struct UMNResult {
    let term: UMNTerm
    let dates: [SchoolDate]
}
struct FetchErr: LocalizedError { let errorDescription: String? }

enum UMN {
    static let months = ["january": 1, "february": 2, "march": 3, "april": 4, "may": 5, "june": 6, "july": 7,
                         "august": 8, "september": 9, "october": 10, "november": 11, "december": 12]
    static let hrURL = URL(string: "https://hr.umn.edu/Benefits/Leaves-and-Time-Away/University-Holiday-Calendars")!

    static func asrURL(_ fy: Int) -> URL {
        URL(string: "https://asr.umn.edu/\(fy)-\(String(format: "%02d", (fy + 1) % 100))-twin-cities-and-rochester-calendar")!
    }

    static func get(_ u: URL) async throws -> String {
        var req = URLRequest(url: u); req.timeoutInterval = 15
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200, let html = String(data: data, encoding: .utf8) else {
            throw FetchErr(errorDescription: "連不到學校網站，或學校還沒公布新的行事曆")
        }
        return html
    }

    static func fetchAll(now: Date = Date()) async throws -> UMNResult {
        let cl = Calendar.current
        let y = cl.component(.year, from: now), mo = cl.component(.month, from: now)
        let fy = mo >= 7 ? y : y - 1                              // 學年 7 月開始
        let au = asrURL(fy)
        let asr = try await get(au)
        let hr = try? await get(hrURL)                            // 假日頁抓不到也沒關係

        // 1. 學期日期
        var start: [String: Date] = [:], end: [String: Date] = [:], out: [SchoolDate] = []
        var sec = "", sy = 0
        for l in lines(asr) {
            if let r = l.range(of: #"(Fall|Spring) Semester (\d{4})"#, options: .regularExpression) {
                let h = String(l[r]); sec = h.hasPrefix("Fall") ? "Fall" : "Spring"; sy = Int(h.suffix(4)) ?? y
                continue
            }
            if !l.contains("\t") && l.range(of: "Session", options: .caseInsensitive) != nil { sec = ""; continue }
            let c = cells(l)
            guard !sec.isEmpty, c.count >= 2 else { continue }
            let en = c[c.count - 1], ev = en.lowercased(), ds = days(c[0], sy)
            guard !ds.isEmpty else { continue }
            let zhSec = sec == "Fall" ? "秋季" : "春季"
            var t = en, k = "other"
            if ev.contains("classes begin") { start[sec] = ds[0]; t = "\(zhSec)開學"; k = "term" }
            else if ev.contains("last day of instruction") { end[sec] = ds[0]; t = "最後上課日"; k = "term" }
            else if ev.contains("study day") { t = "讀書日"; k = "exam" }
            else if ev.contains("final exam") { t = "期末考"; k = "exam" }
            else if ev.contains("end of the term") { t = "\(zhSec)學期結束"; k = "term" }
            else if ev.contains("break") || ev.contains("holiday") || ev.contains("no class") { k = "holiday" }
            for d in ds { out.append(SchoolDate(date: ymd.string(from: d), title: t, en: "\(en) (\(sec) \(sy))", kind: k)) }
        }

        // 2. 大學假日 (Twin Cities 那一張表)
        if let hr {
            let ls = lines(hr)
            if let i = ls.firstIndex(where: { $0.contains("Rochester and Twin Cities Holiday Calendar") }),
               let j = ls[i...].firstIndex(where: { $0.contains("\(fy)-\(fy + 1) University Holidays") }) {
                let tg = thanksgiving(fy)
                for l in ls[(j + 1)...] {
                    let c = cells(l)
                    if c.count < 2 { if !l.contains("\t") { break } else { continue } }   // 表格結束
                    guard let d = hrDate(c[0], fy) else { continue }
                    let en = c[1]
                    let z = zhHoliday(en)
                    var t = z.0, k = z.1
                    if k == "float", let tg, cl.isDate(d, inSameDayAs: cl.date(byAdding: .day, value: 1, to: tg)!) {
                        t = "感恩節假期"; k = "holiday"                         // 感恩節隔天也放假
                    }
                    out.append(SchoolDate(date: ymd.string(from: d), title: t, en: en, kind: k))
                }
            }
        }

        // 3. 本學期: 秋季還沒結束就用秋季，不然用春季
        let today = cl.startOfDay(for: now)
        let pick = (end["Fall"].map { today <= $0 } ?? false) ? "Fall" : "Spring"
        guard let a = start[pick], let b = end[pick] else {
            throw FetchErr(errorDescription: "找不到學期日期，學校網頁格式可能改了")
        }
        let uniq = Array(Set(out)).sorted { ($0.date, $0.title) < ($1.date, $1.title) }
        return UMNResult(term: UMNTerm(name: "\(pick) \(cl.component(.year, from: a))", start: a, end: b, src: au), dates: uniq)
    }

    static func zhHoliday(_ en: String) -> (String, String) {
        let e = en.lowercased()
        if e.contains("floating") { return ("大學浮動假日", "float") }
        let map: [(String, String)] = [("labor", "勞動節"), ("thanksgiving", "感恩節"), ("christmas", "聖誕節"),
                                       ("new year", "元旦"), ("martin luther king", "金恩紀念日"),
                                       ("memorial", "陣亡將士紀念日"), ("juneteenth", "六月節"), ("independence", "美國國慶日")]
        for (k, v) in map where e.contains(k) { return (v, "holiday") }
        return (en, "holiday")
    }

    // "Thursday, November 26" / "Friday, July 3, 2026"
    static func hrDate(_ s: String, _ fy: Int) -> Date? {
        let w = s.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard let mi = w.firstIndex(where: { months[$0] != nil }), mi + 1 < w.count,
              let m = months[w[mi]], let d = Int(w[mi + 1]) else { return nil }
        let yr = (mi + 2 < w.count ? Int(w[mi + 2]) : nil) ?? (m >= 7 ? fy : fy + 1)
        return Calendar.current.date(from: DateComponents(year: yr, month: m, day: d))
    }

    static func cells(_ l: String) -> [String] {
        l.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // HTML -> 一行一列，欄位用 tab 分開
    static func lines(_ html: String) -> [String] {
        var s = html.replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ")
        for (a, b) in [("</tr>", "\n"), ("</h2>", "\n"), ("</h3>", "\n"), ("</td>", "\t"), ("</th>", "\t")] {
            s = s.replacingOccurrences(of: a, with: b, options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#8211;", with: "-").replacingOccurrences(of: "&ndash;", with: "-")
            .replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        return s.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    // "September 8" / "December 17-19, 21-23" -> 日期們
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

    static func thanksgiving(_ y: Int) -> Date? {
        Calendar.current.date(from: DateComponents(year: y, month: 11, weekday: 5, weekdayOrdinal: 4))
    }
}

// 把抓到的資料存進課表檔
func saveSchool(_ r: UMNResult) {
    var (sf, bad) = loadSched()
    if bad { return }
    sf.school = r.dates
    sf.termStart = ymd.string(from: r.term.start)
    sf.termEnd = ymd.string(from: r.term.end)
    writeSched(sf)
    UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "schoolFetched")
    UserDefaults.standard.set(r.term.name, forKey: "schoolTerm")
}
