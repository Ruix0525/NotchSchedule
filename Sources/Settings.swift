// 設定視窗: 課表編輯、學期與假日、行事曆、一般
import SwiftUI
import AppKit
import EventKit
import ServiceManagement
import UserNotifications

let hmf = fm("HH:mm")
let palette = ["#E0E680", "#DED4AB", "#EDCC73", "#ADD9E6", "#F4B6C2", "#C3B1E1", "#B5EAD7", "#FFDAC1", "#C7CEEA", "#F7D794"]
let dayZh = ["", "一", "二", "三", "四", "五", "六", "日"]
let ldf: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "zh_TW"); f.dateFormat = "yyyy/M/d EEEE"; return f }()

// MARK: - 編輯用的資料結構 (一門課 = 多個上課時段)
struct Meeting: Identifiable, Equatable {
    var id = UUID()
    var days: Set<Int> = []
    var start = hmf.date(from: "09:00")!
    var end = hmf.date(from: "09:50")!
    var type = "Lecture"
    var room = ""
}

struct Course: Identifiable, Equatable {
    var id = UUID()
    var code = "", name = ""
    var color = Color(hex: "#ADD9E6")
    var url = ""
    var meetings: [Meeting] = []
    static let blank = Course()
    var summary: String {
        meetings.map { m in m.days.sorted().map { dayZh[$0] }.joined() + " " + tf.string(from: m.start) }
            .joined(separator: "、")
    }
}

final class Store: ObservableObject {
    @Published var courses: [Course] = [] { didSet { autosave() } }
    @Published var termOn = false { didSet { autosave() } }
    @Published var termStart = Date() { didSet { autosave() } }
    @Published var termEnd = Date() { didSet { autosave() } }
    @Published var holidays: [Date] = [] { didSet { autosave() } }
    @Published var broken = false
    var loading = false
    var onSave: (() -> Void)?

    // JSON -> 編輯格式 (同一門課、同時間地點的合併成一個時段)
    func load() {
        loading = true; defer { loading = false }
        let (sf, bad) = loadSched(); broken = bad
        var cs: [Course] = []
        for c in sf.classes {
            let i: Int
            if let j = cs.firstIndex(where: { $0.code == c.code }) { i = j }
            else {
                cs.append(Course(code: c.code, name: c.name, color: Color(hex: sf.colors[c.code] ?? "#C8C8C8"), url: c.url ?? ""))
                i = cs.count - 1
            }
            if cs[i].url.isEmpty, let u = c.url { cs[i].url = u }
            if let k = cs[i].meetings.firstIndex(where: {
                hmf.string(from: $0.start) == c.start && hmf.string(from: $0.end) == c.end && $0.type == c.type && $0.room == c.room
            }) {
                cs[i].meetings[k].days.insert(c.day)
            } else {
                cs[i].meetings.append(Meeting(days: [c.day], start: hmf.date(from: c.start) ?? Date(),
                                              end: hmf.date(from: c.end) ?? Date(), type: c.type, room: c.room))
            }
        }
        courses = cs
        termOn = sf.termStart != nil || sf.termEnd != nil
        termStart = sf.termStart.flatMap { ymd.date(from: $0) } ?? Date()
        termEnd = sf.termEnd.flatMap { ymd.date(from: $0) } ?? Date()
        holidays = (sf.skip ?? []).compactMap { ymd.date(from: $0) }.sorted()
    }

    func autosave() { if !loading && !broken { save() } }

    // 編輯格式 -> JSON
    func save() {
        var cls: [C] = [], cols: [String: String] = [:]
        for c in courses where !c.code.trimmingCharacters(in: .whitespaces).isEmpty {
            cols[c.code] = c.color.hex
            for m in c.meetings {
                for d in m.days.sorted() {
                    cls.append(C(day: d, start: hmf.string(from: m.start), end: hmf.string(from: m.end), code: c.code,
                                 name: c.name, type: m.type, room: m.room, url: c.url.isEmpty ? nil : c.url))
                }
            }
        }
        cls.sort { ($0.day, $0.start) < ($1.day, $1.start) }
        writeSched(SFile(colors: cols, classes: cls,
                         termStart: termOn ? ymd.string(from: termStart) : nil,
                         termEnd: termOn ? ymd.string(from: termEnd) : nil,
                         skip: holidays.isEmpty ? nil : holidays.map { ymd.string(from: $0) },
                         school: loadSched().0.school))                    // 學校日期保留
        onSave?()
    }
}

// MARK: - 設定視窗
struct SettingsView: View {
    @ObservedObject var s: Store
    @ObservedObject var m: M
    var body: some View {
        TabView {
            CoursesTab(s: s).tabItem { Label("課表", systemImage: "list.bullet.rectangle") }
            TermTab(s: s).tabItem { Label("學期與假日", systemImage: "calendar.badge.clock") }
            CalTab(m: m).tabItem { Label("行事曆", systemImage: "calendar") }
            GeneralTab().tabItem { Label("一般", systemImage: "gearshape") }
        }
        .padding(12)
        .frame(minWidth: 760, minHeight: 520)
    }
}

// MARK: 課表
struct CoursesTab: View {
    @ObservedObject var s: Store
    @State var sel: UUID?

    func bind(_ id: UUID) -> Binding<Course> {
        Binding(get: { s.courses.first { $0.id == id } ?? .blank },
                set: { v in if let i = s.courses.firstIndex(where: { $0.id == id }) { s.courses[i] = v } })
    }
    func add() {
        var c = Course()
        c.color = Color(hex: palette[s.courses.count % palette.count])
        c.meetings = [Meeting()]
        s.courses.append(c); sel = c.id
    }
    func remove() {
        guard let id = sel else { return }
        sel = nil
        s.courses.removeAll { $0.id == id }
    }

    var body: some View {
        VStack(spacing: 0) {
            if s.broken {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("schedule.json 格式有誤，修好之前不會自動儲存，以免蓋掉你的資料。")
                    Spacer()
                    Button("在 Finder 顯示") { NSWorkspace.shared.activateFileViewerSelecting([sfile]) }
                    Button("重新讀取") { s.load() }
                }
                .font(.caption).padding(8).background(Color.orange.opacity(0.12))
            }
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    List(selection: $sel) {
                        ForEach(s.courses) { c in
                            HStack(spacing: 10) {
                                Circle().fill(c.color).frame(width: 12, height: 12)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(c.code.isEmpty ? "未命名課程" : c.code).fontWeight(.semibold)
                                    Text(c.summary.isEmpty ? "尚未設定時段" : c.summary)
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            .padding(.vertical, 3)
                            .tag(c.id)
                        }
                    }
                    Divider()
                    HStack(spacing: 2) {
                        Button { add() } label: { Image(systemName: "plus").frame(width: 22, height: 20) }
                        Button { remove() } label: { Image(systemName: "minus").frame(width: 22, height: 20) }.disabled(sel == nil)
                        Spacer()
                        ImportMenu(s: s)
                    }
                    .buttonStyle(.borderless).padding(6)
                }
                .frame(width: 230)
                Divider()
                Group {
                    if let id = sel, s.courses.contains(where: { $0.id == id }) {
                        CourseEditor(c: bind(id)).id(id)
                    } else if s.courses.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "books.vertical").font(.system(size: 40)).foregroundStyle(.secondary)
                            Text("還沒有課程").font(.title3)
                            Button("新增第一門課") { add() }.buttonStyle(.borderedProminent)
                            Text("或用左下角「匯入」：讓 AI 幫你把課表截圖轉好再貼進來").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("從左邊選一門課來編輯").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if sel == nil { sel = s.courses.first?.id } }
    }
}

struct CourseEditor: View {
    @Binding var c: Course
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // 課號、課名、顏色
                HStack(alignment: .top, spacing: 14) {
                    RoundedRectangle(cornerRadius: 6).fill(c.color).frame(width: 8, height: 52)
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("課號，例如 PHYS 2201", text: $c.code)
                            .textFieldStyle(.plain).font(.system(size: 22, weight: .bold))
                        TextField("課名，例如 Thermo & Stat Phys", text: $c.name)
                            .textFieldStyle(.plain).font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 8) {
                    Text("顏色").foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                    ForEach(palette, id: \.self) { h in
                        Circle().fill(Color(hex: h)).frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.primary.opacity(c.color.hex == h ? 0.8 : 0.1), lineWidth: c.color.hex == h ? 2 : 1))
                            .onTapGesture { c.color = Color(hex: h) }
                    }
                    ColorPicker("", selection: $c.color, supportsOpacity: false).labelsHidden()
                }
                HStack(spacing: 8) {
                    Text("連結").foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
                    TextField("Canvas 或課程網址（選填，在課表點卡片可以打開）", text: $c.url)
                }
                Divider()
                HStack {
                    Text("上課時段").font(.headline)
                    Spacer()
                    Button { c.meetings.append(Meeting(type: c.meetings.last?.type ?? "Lecture", room: c.meetings.last?.room ?? "")) } label: {
                        Label("新增時段", systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                }
                if c.meetings.isEmpty {
                    Text("點「新增時段」加入上課時間，例如週一三五的 Lecture、週二的 Discussion。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach($c.meetings) { $mt in
                    MeetingRow(m: $mt) { c.meetings.removeAll { $0.id == mt.id } }
                }
            }
            .padding(22)
        }
    }
}

struct MeetingRow: View {
    @Binding var m: Meeting
    var onDelete: () -> Void
    let types = ["Lecture", "Discussion", "Laboratory", "Recitation", "Seminar", "Office Hours"]

    var minutes: Int { Int(m.end.timeIntervalSince(m.start) / 60) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                ForEach(1...7, id: \.self) { d in
                    let on = m.days.contains(d)
                    Text(dayZh[d])
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 32, height: 28)
                        .background(on ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(on ? Color.white : Color.primary)
                        .contentShape(Rectangle())
                        .onTapGesture { if on { m.days.remove(d) } else { m.days.insert(d) } }
                }
                Spacer()
                Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("刪除這個時段")
            }
            HStack(spacing: 8) {
                DatePicker("", selection: $m.start, displayedComponents: .hourAndMinute).labelsHidden()
                Text("–")
                DatePicker("", selection: $m.end, displayedComponents: .hourAndMinute).labelsHidden()
                if minutes > 0 {
                    Text("\(minutes) 分鐘").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("結束時間要晚於開始").font(.caption).foregroundStyle(.red)
                }
            }
            HStack(spacing: 8) {
                Picker("", selection: $m.type) {
                    ForEach(types.contains(m.type) ? types : types + [m.type], id: \.self) { Text($0) }
                }
                .labelsHidden().frame(width: 140)
                TextField("教室，例如 Tate Hall 105", text: $m.room)
            }
            if m.days.isEmpty {
                Text("↑ 點選上課的星期").font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: 學期與假日
struct TermTab: View {
    @ObservedObject var s: Store
    @State var pick = Date()
    @State var busy = false
    @State var msg: String?
    @State var err: String?
    @State var school: [SchoolDate] = []
    @AppStorage("schoolAuto") var auto = true
    @AppStorage("schoolShow") var show = true
    @AppStorage("schoolFetched") var fetched = 0.0
    @AppStorage("schoolTerm") var termName = ""

    func reloadSchool() { school = loadSched().0.school ?? [] }
    func fetch() {
        busy = true; err = nil; msg = nil
        Task {
            do {
                let r = try await UMN.fetchAll()
                await MainActor.run {
                    saveSchool(r); s.load(); reloadSchool(); busy = false
                    msg = "已更新 \(r.term.name)：\(df.string(from: r.term.start)) – \(df.string(from: r.term.end))，共 \(r.dates.count) 個日期"
                }
            } catch {
                await MainActor.run { err = error.localizedDescription; busy = false }
            }
        }
    }
    var upcoming: [SchoolDate] {
        let t = ymd.string(from: Date())
        var seen = Set<String>(), out: [SchoolDate] = []
        for x in school where x.date >= t && !seen.contains(x.title + x.kind) {   // 期末考那種連續的只列第一天
            seen.insert(x.title + x.kind); out.append(x)
            if out.count >= 8 { break }
        }
        return out
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "building.columns.fill").font(.system(size: 22)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("University of Minnesota – Twin Cities").fontWeight(.semibold)
                        Text(fetched > 0 ? "\(termName) · 上次更新 \(ldf.string(from: Date(timeIntervalSince1970: fetched)))"
                                         : "從學校官網抓開學、最後上課日、期末考和所有大學假日")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                    Button(busy ? "更新中…" : "立即更新") { fetch() }.disabled(busy)
                }
                Toggle("每週自動更新", isOn: $auto)
                Toggle("在課表上顯示學校日期（🎓 開頭的小色條）", isOn: $show)
                if let m = msg { Label(m, systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption) }
                if let e = err { Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption) }
                if !upcoming.isEmpty {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("接下來的學校日期").font(.caption).foregroundStyle(.secondary)
                        ForEach(upcoming, id: \.self) { x in
                            HStack(spacing: 8) {
                                Text(ymd.date(from: x.date).map { ldf.string(from: $0) } ?? x.date)
                                    .font(.system(size: 12, design: .monospaced)).frame(width: 170, alignment: .leading)
                                Text(x.title).font(.system(size: 12, weight: .medium))
                                if x.kind == "holiday" { Text("不上課").font(.system(size: 10)).padding(.horizontal, 5)
                                    .background(Capsule().fill(Color.red.opacity(0.15))) }
                                Spacer()
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } header: { Text("學校行事曆") } footer: {
                Text("資料來源：asr.umn.edu（學期日期）與 hr.umn.edu（大學假日）。放假日會自動不顯示課程。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Toggle("只在學期期間顯示課程", isOn: $s.termOn)
                if s.termOn {
                    DatePicker("開學日", selection: $s.termStart, displayedComponents: .date)
                    DatePicker("最後上課日", selection: $s.termEnd, displayedComponents: .date)
                }
            } footer: {
                Text("放寒暑假時就不會顯示課程，也不會跳「下一堂」提醒。行事曆事件不受影響。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("自己加的放假日（這些日子不顯示課程）") {
                if s.holidays.isEmpty { Text("還沒有放假日").foregroundStyle(.secondary) }
                ForEach(s.holidays, id: \.self) { d in
                    HStack {
                        Text(ldf.string(from: d))
                        Spacer()
                        Button { s.holidays.removeAll { $0 == d } } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    DatePicker("新增放假日", selection: $pick, displayedComponents: .date)
                    Button("加入") {
                        let d = Calendar.current.startOfDay(for: pick)
                        if !s.holidays.contains(d) { s.holidays = (s.holidays + [d]).sorted() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { reloadSchool() }
    }
}

// MARK: 行事曆 (Google 行事曆透過 macOS 帳號同步)
struct CalTab: View {
    @ObservedObject var m: M
    @AppStorage("cal") var calOn = false
    @AppStorage("allday") var allDay = true
    @State var status = EKEventStore.authorizationStatus(for: .event)
    @State var hidden = Set(UserDefaults.standard.stringArray(forKey: "hiddenCals") ?? [])
    @AppStorage("evRemind") var evRemind = false
    @State var hT: [String] = []
    @State var hI: [String] = []
    func loadHidden() {
        hT = UserDefaults.standard.stringArray(forKey: "hiddenTitles") ?? []
        hI = UserDefaults.standard.stringArray(forKey: "hiddenIds") ?? []
    }

    func request() {
        m.requestCal { ok in
            status = EKEventStore.authorizationStatus(for: .event)
            if !ok { calOn = false }
            m.reloadSoon()
        }
    }
    func toggle(_ id: String, _ v: Bool) {
        if v { hidden.remove(id) } else { hidden.insert(id) }
        UserDefaults.standard.set(Array(hidden), forKey: "hiddenCals")
        m.reloadSoon()
    }
    func openPane(_ s: String) { if let u = URL(string: s) { NSWorkspace.shared.open(u) } }

    var body: some View {
        let cals = status == .fullAccess ? m.es.calendars(for: .event) : []
        let groups = Dictionary(grouping: cals, by: { $0.source.title })
        Form {
            Section {
                Toggle("在瀏海課表顯示行事曆", isOn: $calOn)
                    .onChange(of: calOn) { _, v in if v { request() } else { m.reloadSoon() } }
                Toggle("顯示全天 / 跨日活動（日期下方的小色條）", isOn: $allDay).disabled(!calOn)
                Toggle("倒數、提醒和「下一堂」也算行事曆活動", isOn: $evRemind).disabled(!calOn)
                if status == .denied || status == .restricted {
                    HStack {
                        Text("沒有行事曆權限").foregroundStyle(.red)
                        Spacer()
                        Button("打開隱私權設定") { openPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") }
                    }
                } else if status != .fullAccess {
                    Button("允許存取行事曆") { request() }
                }
            }
            if calOn && status == .fullAccess {
                ForEach(groups.keys.sorted(), id: \.self) { k in
                    Section(k) {
                        ForEach(groups[k] ?? [], id: \.calendarIdentifier) { c in
                            Toggle(isOn: Binding(get: { !hidden.contains(c.calendarIdentifier) },
                                                 set: { toggle(c.calendarIdentifier, $0) })) {
                                HStack(spacing: 8) {
                                    Circle().fill(Color(nsColor: c.color)).frame(width: 10, height: 10)
                                    Text(c.title)
                                }
                            }
                        }
                    }
                }
            }
            if calOn {
                Section("已隱藏的活動") {
                    if hT.isEmpty && hI.isEmpty {
                        Text("在課表上點活動 → 隱藏，就會出現在這裡。").foregroundStyle(.secondary)
                    }
                    ForEach(hT, id: \.self) { t in
                        HStack {
                            Image(systemName: "eye.slash").foregroundStyle(.secondary)
                            Text(t)
                            Text("（所有同名）").foregroundStyle(.secondary)
                            Spacer()
                            Button("恢復") {
                                hT.removeAll { $0 == t }
                                UserDefaults.standard.set(hT, forKey: "hiddenTitles")
                            }
                        }
                    }
                    if !hI.isEmpty {
                        HStack {
                            Text("單次隱藏的活動 \(hI.count) 個")
                            Spacer()
                            Button("全部恢復") { hI = []; UserDefaults.standard.set(hI, forKey: "hiddenIds") }
                        }
                    }
                }
            }
            Section("加入 Google 行事曆") {
                Text("1. 打開「網際網路帳號」，登入你的 Google 帳號\n2. 確認「行事曆」有打開\n3. 回到這裡，勾選要顯示的日曆")
                    .font(.callout)
                Button("打開網際網路帳號") { openPane("x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") }
                Text("Google 上新增或修改的活動會自動同步過來，包含重複活動、全天活動和日曆顏色。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { status = EKEventStore.authorizationStatus(for: .event); loadHidden() }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in loadHidden() }
    }
}

// MARK: 一般
struct GeneralTab: View {
    @AppStorage("appearance") var appearance = 0
    @AppStorage("accent") var accent = "#0A84FF"
    @AppStorage("lead") var lead = 10
    @AppStorage("pop") var pop = true
    @AppStorage("noti") var noti = true
    @AppStorage("axis") var axis = false
    @AppStorage("wing") var wing = true
    @AppStorage("weekStart") var weekStart = 0
    @AppStorage("weekend") var weekend = true
    @AppStorage("autoUpdate") var autoUpdate = true
    @AppStorage("autoInstall") var autoInstall = true
    @State var login = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("外觀") {
                Picker("主題", selection: $appearance) {
                    Text("跟隨系統").tag(0)
                    Text("淺色").tag(1)
                    Text("深色").tag(2)
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("強調色")
                    Spacer()
                    ForEach(accents.indices, id: \.self) { i in
                        let a = accents[i]
                        Circle().fill(Color(hex: a.1)).frame(width: 22, height: 22)
                            .overlay(Circle().stroke(Color.primary.opacity(accent == a.1 ? 0.85 : 0), lineWidth: 2).padding(-3))
                            .contentShape(Circle())
                            .onTapGesture { accent = a.1 }
                            .help(a.0)
                    }
                }
            }
            Section("顯示") {
                Picker("課表樣式", selection: $axis) {
                    Text("卡片列表").tag(false)
                    Text("時間軸").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("每週從", selection: $weekStart) {
                    Text("週日").tag(0)
                    Text("週一").tag(1)
                }
                .pickerStyle(.segmented)
                Toggle("顯示週六、週日（關掉的話，週末有活動才會出現）", isOn: $weekend)
                HStack {
                    Toggle("瀏海倒數（開始前 15 分鐘起，在瀏海兩側顯示）", isOn: $wing)
                    Spacer()
                    Button { NotificationCenter.default.post(name: .nsDemo, object: nil) } label: {
                        Label("預覽", systemImage: "play.fill")
                    }
                    .help("看看瀏海倒數的樣子：先顯示「上課前」，再顯示「上課中」")
                }
            }
            Section("開始前提醒") {
                Picker("提前", selection: $lead) {
                    Text("關閉").tag(0)
                    ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) 分鐘").tag($0) }
                }
                Toggle("自動彈出課表", isOn: $pop).disabled(lead == 0)
                HStack {
                    Toggle("發送系統通知", isOn: $noti).disabled(lead == 0)
                    Spacer()
                    Button { NotificationCenter.default.post(name: .nsDemoRemind, object: nil) } label: {
                        Label("預覽提醒", systemImage: "bell.fill")
                    }
                    .disabled(lead == 0)
                }
                    .onChange(of: noti) { _, v in
                        if v { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
                    }
            }
            Section("更新") {
                HStack {
                    Text("目前版本 v\(Updater.current)")
                    Spacer()
                    Button("檢查更新") { NotificationCenter.default.post(name: .nsCheckUpdate, object: nil) }
                }
                Toggle("自動檢查新版（每 6 小時）", isOn: $autoUpdate)
                Toggle("有新版時自動安裝（沒在用的時候）", isOn: $autoInstall).disabled(!autoUpdate)
            }
            Section("其他") {
                Toggle("開機自動啟動", isOn: $login)
                    .onChange(of: login) { _, v in
                        if v { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
                        login = SMAppService.mainApp.status == .enabled
                    }
                HStack {
                    Text("新手教學")
                    Spacer()
                    Button("重播") { NotificationCenter.default.post(name: .nsTour, object: nil) }
                }
                HStack {
                    Text("進階：課表檔案 schedule.json")
                    Spacer()
                    Button("在 Finder 顯示") { NSWorkspace.shared.activateFileViewerSelecting([sfile]) }
                }
            }
        }
        .formStyle(.grouped)
    }
}
