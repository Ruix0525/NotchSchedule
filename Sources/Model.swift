// 資料層: 背景讀取課表 + 行事曆，算好版面再交給畫面 (避免卡頓)
import SwiftUI
import AppKit
import EventKit

struct Occ: Identifiable {
    let id: String
    let st, en: Date
    let c, n, k, r: String
    let col: Color
    var url: String? = nil
    var note: String? = nil
    var all = false                          // 顯示在上方小條 (全天 / 跨日 / 超長)
    var multi = false                        // 跨日或超長的「有時間」事件
    var isClass = false                      // 課表裡的課 (不是行事曆活動)
}

// 隱藏行事曆活動: 單次 or 同名全部
func hideEvent(_ o: Occ, all: Bool) {
    let ud = UserDefaults.standard
    let k = all ? "hiddenTitles" : "hiddenIds", v = all ? o.c : o.id
    var a = ud.stringArray(forKey: k) ?? []
    if !a.contains(v) { a.append(v); ud.set(a, forKey: k) }
}

struct Lane { let i, n: Int }

// 主題: 淺色 / 深色 + 強調色
struct Theme: Equatable {
    var dark = false
    var accent = Color(hex: "#0A84FF")
    var bg: Color { dark ? Color(red: 0.11, green: 0.11, blue: 0.12) : .white }
    var fg: Color { dark ? .white : .black }
    var sub: Color { dark ? Color.white.opacity(0.55) : Color.black.opacity(0.5) }
    var line: Color { dark ? Color.white.opacity(0.09) : Color.black.opacity(0.07) }
    var soft: Color { dark ? Color.white.opacity(0.07) : Color.black.opacity(0.04) }
}
let accents: [(String, String)] = [("藍", "#0A84FF"), ("靛", "#5E5CE6"), ("紫", "#BF5AF2"), ("粉", "#FF375F"),
                                   ("橘", "#FF9F0A"), ("綠", "#30D158"), ("青", "#40C8E0")]                // 重疊事件並排: 第 i 條 / 共 n 條

// 每次資料或時間變動時「一次算好」的版面資料
struct Snap {
    var mon = Date()
    var cols: [Int] = Array(0..<5)
    var byDay: [Int: [Occ]] = [:]
    var allByDay: [Int: [Occ]] = [:]
    var lane: [String: Lane] = [:]
    var hours = (8, 18)
    var panelW: CGFloat = 720
    var panelH: CGFloat = 480
    var allMax = 0
}

final class UI: ObservableObject {
    @Published var open = false
    @Published var tour: Int? = nil          // 新手教學進行到第幾步
    var onTourEnd: (() -> Void)?
    @Published var newVer: String?           // GitHub 上有新版
    var newURL: URL?
    @Published var updating = false
    func endTour() { tour = nil; onTourEnd?() }
    @Published var nw: CGFloat = 200
    @Published var nh: CGFloat = 32
}

let ymd = fm("yyyy-MM-dd")

final class M: ObservableObject {
    @Published var now = Date()
    @Published private(set) var snap = Snap()
    @Published var bad = false
    @Published var axis = false
    @Published var wing = true
    @Published var theme = Theme()
    @Published var wkOff = 0                 // 0 = 本週, 1 = 下週, -1 = 上週
    @Published var demo: Occ?                // 倒數預覽用
    private(set) var occs: [Occ] = []        // 有時間的 (排序好)
    private(set) var alls: [Occ] = []
    private(set) var foc: [Occ] = []         // 倒數/提醒/上方提示 會看的 (預設只有課)
    let es = EKEventStore()
    let cl = Calendar.current
    let ud = UserDefaults.standard
    var maxH: CGFloat = 800                  // 螢幕允許的最大高度 (AD 設定)
    var nh: CGFloat = 32
    private let q = DispatchQueue(label: "notchschedule.reload", qos: .userInitiated)
    private var pend: DispatchWorkItem?
    private var loadedBase = Date.distantPast

    static let hourH: CGFloat = 34, cardH: CGFloat = 84, chipH: CGFloat = 18, chipMax = 3

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: es, queue: .main) { [weak self] _ in
            self?.reloadSoon(0.5)
        }
    }

    // 本週第一天 (預設週日開始，跟 Google 日曆一樣；設定可改週一)
    var base: Date {
        let w = cl.component(.weekday, from: now)              // 1 = 週日
        let back = ud.integer(forKey: "weekStart") == 1 ? (w + 5) % 7 : w - 1
        return cl.date(byAdding: .day, value: -back, to: cl.startOfDay(for: now))!
    }
    func day(_ i: Int) -> Date { cl.date(byAdding: .day, value: i, to: snap.mon)! }
    func on(_ i: Int) -> [Occ] { snap.byDay[i] ?? [] }
    func allOn(_ i: Int) -> [Occ] { snap.allByDay[i] ?? [] }
    func isLive(_ o: Occ) -> Bool { o.st <= now && now < o.en }
    func mod(_ d: Date) -> CGFloat { CGFloat(cl.component(.hour, from: d) * 60 + cl.component(.minute, from: d)) }

    var live: Occ? { foc.first { isLive($0) } }
    var next: Occ? { foc.first { $0.st > now } }
    var soon: Occ? {
        if let l = live { return l }
        if let x = next, x.st.timeIntervalSince(now) <= 15 * 60 { return x }
        return nil
    }

    func shift(_ d: Int) { wkOff = max(-1, min(wkOff + d, 2)); derive() }

    // 每 30 秒: 只更新時間 + 重算版面 (很便宜)；換週才重新讀資料
    func tick() {
        now = Date()
        if base != loadedBase { reload() } else { derive() }
    }

    // 連續觸發時合併成一次
    func reloadSoon(_ delay: Double = 0.25) {
        pend?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.reload() }
        pend = w
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
    }

    // 在背景讀課表 + 行事曆，不卡畫面
    func reload() {
        now = Date()
        let b0 = base, cal = ud.bool(forKey: "cal"), allday = ud.bool(forKey: "allday")
        let hid = Set(ud.stringArray(forKey: "hiddenCals") ?? [])
        let hT = Set(ud.stringArray(forKey: "hiddenTitles") ?? []), hI = Set(ud.stringArray(forKey: "hiddenIds") ?? [])
        let granted = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        let showSchool = ud.bool(forKey: "schoolShow")
        q.async { [weak self] in
            guard let self else { return }
            let cl = self.cl
            let (sf, bad) = loadSched()
            var o: [Occ] = [], a: [Occ] = []
            // 學校行事曆: 放假日不上課，並顯示在日期下方
            var skip = Set(sf.skip ?? [])
            let kc = ["holiday": "#FFB3A7", "term": "#9FE3C1", "exam": "#C9B6F2", "float": "#E3E3E8", "other": "#E3E3E8"]
            let kz = ["holiday": "放假", "term": "學期", "exam": "考試", "float": "浮動假日", "other": "學校"]
            for x in sf.school ?? [] {
                if x.kind == "holiday" { skip.insert(x.date) }
                guard showSchool, let d = ymd.date(from: x.date) else { continue }
                a.append(Occ(id: "umn-\(x.date)-\(x.title)", st: d, en: cl.date(byAdding: .day, value: 1, to: d)!,
                             c: "🎓 " + x.title, n: "UMN 行事曆", k: kz[x.kind] ?? "學校", r: "",
                             col: Color(hex: kc[x.kind] ?? "#E3E3E8"),
                             note: x.en + (x.kind == "float" ? "\n教職員的假日，有沒有上課以老師公告為準。" : ""), all: true))
            }
            for k in -7..<28 {                                   // 上週 ~ 下下週，一天一天排
                let d = cl.date(byAdding: .day, value: k, to: b0)!
                let wd = (cl.component(.weekday, from: d) + 5) % 7 + 1   // 1 = 週一 ... 7 = 週日
                for c in sf.classes where c.day == wd {
                    let ds = ymd.string(from: d)
                    if let s = sf.termStart, ds < s { continue }
                    if let z = sf.termEnd, ds > z { continue }
                    if skip.contains(ds) { continue }
                    let st = self.at(d, c.start)
                    o.append(Occ(id: "\(c.code)-\(Int(st.timeIntervalSince1970))", st: st, en: self.at(d, c.end),
                                 c: c.code, n: c.name, k: c.type, r: c.room,
                                 col: Color(hex: sf.colors[c.code] ?? "#C8C8C8"), url: c.url, isClass: true))
                }
            }
            if cal && granted {
                let cs = self.es.calendars(for: .event).filter { !hid.contains($0.calendarIdentifier) }
                if !cs.isEmpty {
                    let p = self.es.predicateForEvents(withStart: cl.date(byAdding: .day, value: -7, to: b0)!,
                                                       end: cl.date(byAdding: .day, value: 28, to: b0)!, calendars: cs)
                    for e in self.es.events(matching: p) {
                        let id = "\(e.eventIdentifier ?? "ev")-\(Int(e.startDate.timeIntervalSince1970))"
                        if hT.contains(e.title ?? "") || hI.contains(id) { continue }
                        let long = e.endDate.timeIntervalSince(e.startDate) >= 12 * 3600
                            || !cl.isDate(e.startDate, inSameDayAs: e.endDate.addingTimeInterval(-1))
                        let top = e.isAllDay || long
                        let x = Occ(id: id,
                                    st: e.startDate, en: e.endDate, c: e.title ?? "(無標題)", n: e.calendar.title,
                                    k: e.isAllDay ? "全天" : "行事曆", r: e.location ?? "",
                                    col: Color(nsColor: (e.calendar.color.usingColorSpace(.sRGB) ?? .gray)
                                                .blended(withFraction: 0.5, of: .white) ?? .gray),
                                    url: e.url?.absoluteString, note: e.notes, all: top, multi: top && !e.isAllDay)
                        if top { if allday { a.append(x) } } else { o.append(x) }
                    }
                }
            }
            o.sort { $0.st < $1.st }
            a.sort { ($0.id.hasPrefix("umn") ? 0 : 1, $0.st) < ($1.id.hasPrefix("umn") ? 0 : 1, $1.st) }   // 學校日期排前面
            DispatchQueue.main.async {
                self.bad = bad; self.occs = o; self.alls = a; self.loadedBase = b0
                self.derive()
            }
        }
    }

    // 算版面: 哪一週、哪幾欄、每天的事件、重疊並排、面板大小
    func derive() {
        axis = ud.bool(forKey: "axis"); wing = ud.bool(forKey: "wing")
        foc = ud.bool(forKey: "evRemind") ? occs : occs.filter { $0.isClass }
        let ap = ud.integer(forKey: "appearance")            // 0 跟隨系統 1 淺色 2 深色
        let sysDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let t = Theme(dark: ap == 2 || (ap == 0 && sysDark), accent: Color(hex: ud.string(forKey: "accent") ?? "#0A84FF"))
        if t != theme { theme = t }
        var s = Snap()
        s.mon = cl.date(byAdding: .day, value: 7 * wkOff, to: base)!
        let end = cl.date(byAdding: .day, value: 7, to: s.mon)!
        let days = (0..<8).map { cl.date(byAdding: .day, value: $0, to: s.mon)! }

        for o in occs where o.st >= s.mon && o.st < end {
            let i = cl.dateComponents([.day], from: s.mon, to: cl.startOfDay(for: o.st)).day ?? 0
            s.byDay[i, default: []].append(o)
        }
        for o in alls where o.st < end && o.en > s.mon {
            for i in 0..<7 where o.st < days[i + 1] && o.en > days[i] { s.allByDay[i, default: []].append(o) }
        }
        // 週末欄: 開「顯示週六日」就一直顯示，關掉的話有活動才出現
        let showWE = ud.bool(forKey: "weekend")
        s.cols = (0..<7).filter { i in
            let wd = cl.component(.weekday, from: days[i])
            return showWE || (wd != 1 && wd != 7) || s.byDay[i] != nil || s.allByDay[i] != nil
        }
        let wmap: [Int: CGFloat] = [5: 720, 6: 820, 7: 920]
        s.panelW = wmap[s.cols.count] ?? 720
        s.allMax = s.cols.map { min(s.allByDay[$0]?.count ?? 0, M.chipMax + 1) }.max() ?? 0

        // 重疊的事件分成幾條並排
        for (_, list) in s.byDay {
            var ends: [Date] = [], group: [(String, Int)] = [], gEnd = Date.distantPast
            func flush() { for (id, i) in group { s.lane[id] = Lane(i: i, n: max(ends.count, 1)) }; ends = []; group = [] }
            for o in list {
                if o.st >= gEnd { flush() }
                if let l = ends.firstIndex(where: { $0 <= o.st }) { ends[l] = o.en; group.append((o.id, l)) }
                else { ends.append(o.en); group.append((o.id, ends.count - 1)) }
                gEnd = max(gEnd, o.en)
            }
            flush()
        }

        // 時間軸範圍 (今天在畫面上的話，一定包含「現在」)
        let timed = s.cols.flatMap { s.byDay[$0] ?? [] }
        var a0 = 8, z0 = 18
        if !timed.isEmpty {
            a0 = min(timed.map { cl.component(.hour, from: $0.st) }.min()!, 8)
            z0 = max(timed.map { cl.component(.hour, from: $0.en) + (cl.component(.minute, from: $0.en) > 0 ? 1 : 0) }.max()!, 18)
        }
        if s.cols.contains(where: { cl.isDateInToday(days[$0]) }) {
            let h = cl.component(.hour, from: now)
            a0 = min(a0, h); z0 = max(z0, h + 1)
        }
        s.hours = (max(a0, 0), min(max(z0, a0 + 4), 24))

        // 面板高度跟著內容走
        let headH: CGFloat = 20 + CGFloat(s.allMax) * M.chipH
        let body: CGFloat
        if axis {
            body = headH + CGFloat(s.hours.1 - s.hours.0) * M.hourH
        } else {
            let most = s.cols.map { s.byDay[$0]?.count ?? 0 }.max() ?? 0
            body = headH + CGFloat(max(most, 1)) * M.cardH
        }
        let chrome = nh + 8 + 30 + 10 + 64 + 12 + 16 + (bad ? 26 : 0)
        s.panelH = min(max(chrome + body, 300), maxH)
        snap = s
    }

    func at(_ d: Date, _ s: String) -> Date {
        let x = mins(s)
        return cl.date(bySettingHour: x / 60, minute: x % 60, second: 0, of: d)!
    }

    func requestCal(_ done: @escaping (Bool) -> Void) {
        es.requestFullAccessToEvents { ok, _ in DispatchQueue.main.async { done(ok) } }
    }
}
