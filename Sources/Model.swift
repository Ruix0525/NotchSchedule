// 把課表 + 行事曆事件展開成「這週 + 下週」的實際時段
import SwiftUI
import EventKit

struct Occ: Identifiable {
    let id: String
    let st, en: Date
    let c, n, k, r: String
    let col: Color
}

final class M: ObservableObject {
    @Published var now = Date()
    @Published var occs: [Occ] = []
    @Published var bad = false
    let es = EKEventStore()
    let cl = Calendar.current
    let ud = UserDefaults.standard

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: es, queue: .main) { [weak self] _ in self?.refresh() }
    }

    // 顯示哪一週的週一 (週末時直接顯示下週)
    var mon: Date {
        let w = cl.component(.weekday, from: now)
        var m = cl.date(byAdding: .day, value: -((w + 5) % 7), to: cl.startOfDay(for: now))!
        if w == 1 || w == 7 { m = cl.date(byAdding: .day, value: 7, to: m)! }
        return m
    }
    func day(_ i: Int) -> Date { cl.date(byAdding: .day, value: i, to: mon)! }
    func on(_ d: Date) -> [Occ] { occs.filter { cl.isDate($0.st, inSameDayAs: d) } }
    var live: Occ? { occs.first { $0.st <= now && now < $0.en } }
    var next: Occ? { occs.first { $0.st > now } }

    func at(_ d: Date, _ s: String) -> Date {
        let x = mins(s)
        return cl.date(bySettingHour: x / 60, minute: x % 60, second: 0, of: d)!
    }

    func refresh() {
        now = Date()
        let (sf, b) = loadSched(); bad = b
        var o: [Occ] = []
        for wk in 0..<2 {                                       // 這週 + 下週
            for c in sf.classes {
                let d = cl.date(byAdding: .day, value: 7 * wk + c.day - 1, to: mon)!
                let st = at(d, c.start)
                o.append(Occ(id: "\(c.code)-\(Int(st.timeIntervalSince1970))", st: st, en: at(d, c.end),
                             c: c.code, n: c.name, k: c.type, r: c.room, col: Color(hex: sf.colors[c.code] ?? "#C8C8C8")))
            }
        }
        if ud.bool(forKey: "cal") && EKEventStore.authorizationStatus(for: .event) == .fullAccess {
            let p = es.predicateForEvents(withStart: mon, end: cl.date(byAdding: .day, value: 14, to: mon)!, calendars: nil)
            for e in es.events(matching: p) where !e.isAllDay {
                o.append(Occ(id: "\(e.eventIdentifier ?? "ev")-\(Int(e.startDate.timeIntervalSince1970))",
                             st: e.startDate, en: e.endDate, c: e.title ?? "(無標題)", n: e.calendar.title,
                             k: "行事曆", r: e.location ?? "", col: Color(nsColor: e.calendar.color).opacity(0.45)))
            }
        }
        occs = o.sorted { $0.st < $1.st }
    }

    func requestCal(_ done: @escaping (Bool) -> Void) {
        es.requestFullAccessToEvents { ok, _ in DispatchQueue.main.async { done(ok) } }
    }
}
