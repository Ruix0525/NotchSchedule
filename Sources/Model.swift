// 把課表 + 行事曆事件展開成實際時段
import SwiftUI
import EventKit

struct Occ: Identifiable {
    let id: String
    let st, en: Date
    let c, n, k, r: String
    let col: Color
    var url: String? = nil
    var note: String? = nil
    var all = false                          // 全天事件
}

final class UI: ObservableObject {
    @Published var open = false
    @Published var nw: CGFloat = 200
    @Published var nh: CGFloat = 32
}

let ymd = fm("yyyy-MM-dd")

final class M: ObservableObject {
    @Published var now = Date()
    @Published var occs: [Occ] = []          // 有時間的
    @Published var alls: [Occ] = []          // 全天
    @Published var bad = false
    @Published var axis = false
    @Published var wing = true
    let es = EKEventStore()
    let cl = Calendar.current
    let ud = UserDefaults.standard

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: es, queue: .main) { [weak self] _ in self?.refresh() }
    }

    // 本週週一
    var base: Date {
        let w = cl.component(.weekday, from: now)
        return cl.date(byAdding: .day, value: -((w + 5) % 7), to: cl.startOfDay(for: now))!
    }
    // 顯示哪一週: 週末且這週已經沒東西了 -> 顯示下週
    var mon: Date {
        let b = base, w = cl.component(.weekday, from: now)
        guard w == 1 || w == 7 else { return b }
        let e = cl.date(byAdding: .day, value: 7, to: b)!
        let left = occs.contains { $0.en > now && $0.st < e } || alls.contains { $0.en > now && $0.st < e }
        return left ? b : e
    }
    func day(_ i: Int) -> Date { cl.date(byAdding: .day, value: i, to: mon)! }
    func on(_ d: Date) -> [Occ] { occs.filter { cl.isDate($0.st, inSameDayAs: d) } }
    func allOn(_ d: Date) -> [Occ] {
        let e = cl.date(byAdding: .day, value: 1, to: d)!
        return alls.filter { $0.st < e && $0.en > d }
    }
    // 要顯示的欄: 週一到五，週末有東西才出現
    var cols: [Int] {
        Array(0..<5) + [5, 6].filter { !on(day($0)).isEmpty || !allOn(day($0)).isEmpty }
    }
    var panelW: CGFloat { let w: [Int: CGFloat] = [5: 720, 6: 820, 7: 920]; return w[cols.count] ?? 720 }

    func isLive(_ o: Occ) -> Bool { o.st <= now && now < o.en }
    func mod(_ d: Date) -> CGFloat { CGFloat(cl.component(.hour, from: d) * 60 + cl.component(.minute, from: d)) }

    var live: Occ? { occs.first { isLive($0) } }
    var next: Occ? { occs.first { $0.st > now } }
    var soon: Occ? {
        if let l = live { return l }
        if let x = next, x.st.timeIntervalSince(now) <= 15 * 60 { return x }
        return nil
    }

    var hours: (Int, Int) {
        let w = cols.flatMap { on(day($0)) }
        guard !w.isEmpty else { return (8, 18) }
        let a = w.map { cl.component(.hour, from: $0.st) }.min()!
        let b = w.map { cl.component(.hour, from: $0.en) + (cl.component(.minute, from: $0.en) > 0 ? 1 : 0) }.max()!
        return (min(a, 8), min(max(b, a + 4), 24))
    }

    func at(_ d: Date, _ s: String) -> Date {
        let x = mins(s)
        return cl.date(bySettingHour: x / 60, minute: x % 60, second: 0, of: d)!
    }

    func refresh() {
        now = Date()
        axis = ud.bool(forKey: "axis"); wing = ud.bool(forKey: "wing")
        let (sf, b) = loadSched(); bad = b
        let skip = Set(sf.skip ?? []), b0 = base
        var o: [Occ] = [], a: [Occ] = []
        for wk in 0..<3 {                                       // 這週起三週
            for c in sf.classes {
                let d = cl.date(byAdding: .day, value: 7 * wk + c.day - 1, to: b0)!
                let ds = ymd.string(from: d)
                if let s = sf.termStart, ds < s { continue }
                if let z = sf.termEnd, ds > z { continue }
                if skip.contains(ds) { continue }
                let st = at(d, c.start)
                o.append(Occ(id: "\(c.code)-\(Int(st.timeIntervalSince1970))", st: st, en: at(d, c.end),
                             c: c.code, n: c.name, k: c.type, r: c.room,
                             col: Color(hex: sf.colors[c.code] ?? "#C8C8C8"), url: c.url))
            }
        }
        if ud.bool(forKey: "cal") && EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let hid = Set(ud.stringArray(forKey: "hiddenCals") ?? [])
            let cs = es.calendars(for: .event).filter { !hid.contains($0.calendarIdentifier) }
            if !cs.isEmpty {
                let p = es.predicateForEvents(withStart: b0, end: cl.date(byAdding: .day, value: 21, to: b0)!, calendars: cs)
                for e in es.events(matching: p) {
                    let x = Occ(id: "\(e.eventIdentifier ?? "ev")-\(Int(e.startDate.timeIntervalSince1970))",
                                st: e.startDate, en: e.endDate, c: e.title ?? "(無標題)", n: e.calendar.title,
                                k: e.isAllDay ? "全天" : "行事曆", r: e.location ?? "",
                                col: Color(nsColor: e.calendar.color).opacity(0.45),
                                url: e.url?.absoluteString, note: e.notes, all: e.isAllDay)
                    if e.isAllDay { if ud.bool(forKey: "allday") { a.append(x) } } else { o.append(x) }
                }
            }
        }
        occs = o.sorted { $0.st < $1.st }
        alls = a.sorted { $0.st < $1.st }
    }

    func requestCal(_ done: @escaping (Bool) -> Void) {
        es.requestFullAccessToEvents { ok, _ in DispatchQueue.main.async { done(ok) } }
    }
}
