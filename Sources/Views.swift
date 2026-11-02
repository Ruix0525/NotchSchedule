// 瀏海面板的畫面
import SwiftUI
import AppKit

func fm(_ s: String) -> DateFormatter { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = s; return f }
let tf = fm("h:mm"), af = fm("a"), df = fm("M/d")
func tma(_ d: Date) -> String { "\(tf.string(from: d)) \(af.string(from: d))" }
func mleft(_ a: Date, _ b: Date) -> Int { Int(ceil(b.timeIntervalSince(a) / 60)) }

func dur(_ m: Int) -> String {
    let d = m / 1440, h = m % 1440 / 60, mm = m % 60
    var o: [String] = []
    if d > 0 { o.append("\(d) 天") }
    if h > 0 { o.append("\(h) 小時") }
    if mm > 0 && d == 0 { o.append("\(mm) 分鐘") }
    return o.isEmpty ? "不到 1 分鐘" : o.joined(separator: " ")
}
func short(_ m: Int) -> String { m < 60 ? "\(m) 分" : "\(m / 60):\(String(format: "%02d", m % 60))" }

let zh = ["日", "一", "二", "三", "四", "五", "六"]
func dayName(_ d: Date) -> String {
    let c = Calendar.current
    if c.isDateInToday(d) { return "今天" }
    if c.isDateInTomorrow(d) { return "明天" }
    return "週" + zh[c.component(.weekday, from: d) - 1]
}
let wd = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

// MARK: - 只畫路徑的瀏海形狀 (動畫時只改路徑，不重新排版 -> 流暢)
struct NotchShape: Shape {
    var w: CGFloat, h: CGFloat, r: CGFloat
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(w, h), r) }
        set { w = newValue.first.first; h = newValue.first.second; r = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(bottomLeadingRadius: r, bottomTrailingRadius: r)
            .path(in: CGRect(x: rect.midX - w / 2, y: 0, width: w, height: h))
    }
}

// MARK: - 根視圖: 從瀏海長出來
struct Root: View {
    @ObservedObject var m: M
    @ObservedObject var u: UI
    var onMenu: () -> Void
    static let wingW: CGFloat = 96

    var act: Occ? { m.wing ? m.soon : nil }

    var body: some View {
        let o = u.open, a = act, W = m.snap.panelW, H = m.snap.panelH
        let cw = o ? W : u.nw + (a != nil ? 2 * Root.wingW : 0)
        let shape = NotchShape(w: cw, h: o ? H : u.nh, r: o ? 22 : 10)
        ZStack(alignment: .top) {
            // 背景 + 陰影只畫在形狀上 (便宜)
            shape.fill(o || a == nil ? Color.white : Color.black)
                .shadow(color: .black.opacity(o ? 0.22 : 0), radius: 16, y: 8)
            // 內容一直存在，只用遮罩露出來 -> 打開瞬間不用重建
            SchedView(m: m, open: o, top: u.nh, onMenu: onMenu)
                .frame(width: W, height: H)
                .opacity(o ? 1 : 0)
                .mask(shape)
                .allowsHitTesting(o)
            if let a {
                Wings(o: a, now: m.now, nw: u.nw, nh: u.nh)
                    .frame(width: cw, height: u.nh)
                    .opacity(o ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .opacity(o || a != nil ? 1 : 0)
        .animation(.spring(duration: 0.42, bounce: 0.16), value: o)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: W)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: H)
        .animation(.easeInOut(duration: 0.3), value: a?.id)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - 收起時: 瀏海兩側倒數
struct Wings: View {
    let o: Occ; let now: Date; let nw, nh: CGFloat
    var body: some View {
        let on = o.st <= now
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle().fill(o.col).frame(width: 7, height: 7)
                Text(o.c).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            .frame(width: Root.wingW - 10, alignment: .leading).padding(.leading, 10)
            Spacer().frame(width: nw)
            Text(on ? "剩 \(short(mleft(now, o.en)))" : "\(short(mleft(now, o.st)))後")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(on ? Color.orange : Color.cyan)
                .lineLimit(1).minimumScaleFactor(0.7)
                .frame(width: Root.wingW - 10, alignment: .trailing).padding(.trailing, 10)
        }
        .foregroundStyle(.white)
        .frame(height: nh)
    }
}

// MARK: - 點卡片跳出的詳細資訊
struct Detail: View {
    let o: Occ
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(o.col).frame(width: 5, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.c).font(.headline).lineLimit(2)
                    if !o.n.isEmpty { Text(o.n).font(.subheadline).foregroundStyle(.secondary) }
                }
            }
            Label(o.multi ? "\(dayName(o.st)) \(tma(o.st)) → \(dayName(o.en)) \(tma(o.en))"
                  : o.all ? "\(dayName(o.st)) · 全天" : "\(dayName(o.st)) \(tma(o.st)) – \(tma(o.en))", systemImage: "clock")
            if !o.all && !o.k.isEmpty && o.k != "行事曆" { Label(o.k, systemImage: "tag") }
            if !o.r.isEmpty { Label(o.r, systemImage: "mappin.and.ellipse").lineLimit(3) }
            if let n = o.note, !n.isEmpty {
                Text(n).font(.caption).foregroundStyle(.secondary).lineLimit(8).textSelection(.enabled)
            }
            if let s = o.url, let x = URL(string: s) {
                Button { NSWorkspace.shared.open(x) } label: { Label("打開連結", systemImage: "arrow.up.right.square") }
            }
        }
        .font(.system(size: 12))
        .padding(14)
        .frame(width: 270, alignment: .leading)
    }
}

// MARK: - 列表模式卡片
struct Card: View {
    let o: Occ; let live, past: Bool
    @State var pop = false
    var body: some View {
        VStack(spacing: 1) {
            Text(o.c).font(.system(size: 11.5, weight: .bold))
            Text(o.n).font(.system(size: 10, weight: .semibold))
            Text(o.k).font(.system(size: 9.5)).padding(.top, 2)
            Text("\(tf.string(from: o.st)) - \(tma(o.en))").font(.system(size: 9.5))
            if !o.r.isEmpty { Text(o.r).font(.system(size: 9.5)) }
        }
        .lineLimit(1).minimumScaleFactor(0.75)
        .foregroundStyle(.black)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6).padding(.horizontal, 4)
        .background(o.col)
        .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.18)).frame(height: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.orange, lineWidth: live ? 2.5 : 0))
        .opacity(past ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture { pop = true }
        .popover(isPresented: $pop, arrowEdge: .bottom) { Detail(o: o) }
    }
}

// MARK: - 時間軸模式卡片
struct MiniCard: View {
    let o: Occ; let live, past: Bool
    @State var pop = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(o.c).font(.system(size: 10.5, weight: .bold))
            Text("\(tf.string(from: o.st))\(o.r.isEmpty ? "" : " · " + o.r)").font(.system(size: 9))
        }
        .lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(.black)
        .padding(.leading, 6).padding(.trailing, 3).padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(o.col)
        .overlay(alignment: .leading) { Rectangle().fill(.black.opacity(0.2)).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(.orange, lineWidth: live ? 2 : 0))
        .opacity(past ? 0.4 : 1)
        .contentShape(Rectangle())
        .onTapGesture { pop = true }
        .popover(isPresented: $pop, arrowEdge: .trailing) { Detail(o: o) }
    }
}

// MARK: - 全天事件小條
struct AllDayChip: View {
    let o: Occ
    @State var pop = false
    var body: some View {
        Text(o.c)
            .font(.system(size: 9.5, weight: .semibold)).lineLimit(1)
            .foregroundStyle(.black)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(o.col, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture { pop = true }
            .popover(isPresented: $pop, arrowEdge: .bottom) { Detail(o: o) }
    }
}

// MARK: - 齒輪 (大一點、有 hover 回饋)
struct GearButton: View {
    var action: () -> Void
    @State var hov = false
    var body: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(hov ? Color.black.opacity(0.75) : Color.gray)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Color.black.opacity(hov ? 0.09 : 0.04)))
            .contentShape(Circle())
            .onHover { hov = $0 }
            .onTapGesture { action() }
            .help("設定")
    }
}

// MARK: - 每一欄的標題 (+ 全天/跨日事件，最多 3 個)
struct DayTop: View {
    @ObservedObject var m: M
    let i: Int
    var body: some View {
        let d = m.day(i), list = m.allOn(i)
        VStack(spacing: 2) {
            Text("\(wd[i]) \(df.string(from: d))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Calendar.current.isDateInToday(d) ? Color.orange : Color.black.opacity(0.6))
                .frame(height: 18)
            ForEach(list.prefix(M.chipMax)) { o in AllDayChip(o: o).frame(height: M.chipH - 2) }
            if list.count > M.chipMax {
                Text("+\(list.count - M.chipMax) 個").font(.system(size: 9.5)).foregroundStyle(.gray).frame(height: M.chipH - 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - 時間軸 (可捲動，打開時自動捲到現在)
struct AxisGrid: View {
    @ObservedObject var m: M
    let open: Bool
    let gut: CGFloat = 22, sp: CGFloat = 6

    var target: Int {
        let hr = m.snap.hours
        let todayShown = m.snap.cols.contains { Calendar.current.isDateInToday(m.day($0)) }
        let h = todayShown ? Calendar.current.component(.hour, from: m.now) - 1 : 8
        return min(max(h, hr.0), max(hr.1 - 1, hr.0))
    }

    var body: some View {
        let hr = m.snap.hours, cs = m.snap.cols, hh = M.hourH
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: sp) {
                Color.clear.frame(width: gut, height: 1)
                ForEach(cs, id: \.self) { i in DayTop(m: m, i: i) }
            }
            GeometryReader { g in
                let cw = (g.size.width - gut - sp * CGFloat(cs.count)) / CGFloat(cs.count)
                ScrollViewReader { pr in
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                ForEach(hr.0..<hr.1, id: \.self) { h in
                                    HStack(alignment: .top, spacing: 0) {
                                        Text(h == 12 ? "12" : "\(h % 12)").font(.system(size: 9)).foregroundStyle(.gray)
                                            .frame(width: gut, alignment: .leading).offset(y: -5)
                                        Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
                                    }
                                    .frame(height: hh, alignment: .top)
                                    .id(h)
                                }
                            }
                            ForEach(cs.indices, id: \.self) { j in
                                let x0 = gut + sp + CGFloat(j) * (cw + sp)
                                ForEach(m.on(cs[j])) { o in
                                    let ln = m.snap.lane[o.id] ?? Lane(i: 0, n: 1)
                                    let w = cw / CGFloat(ln.n)
                                    let y = (m.mod(o.st) - CGFloat(hr.0 * 60)) / 60 * hh
                                    let h = max(CGFloat(o.en.timeIntervalSince(o.st)) / 3600 * hh - 1, 15)
                                    MiniCard(o: o, live: m.isLive(o), past: o.en <= m.now)
                                        .frame(width: w - 1, height: h)
                                        .offset(x: x0 + CGFloat(ln.i) * w, y: y)
                                }
                            }
                            if let j = cs.firstIndex(where: { Calendar.current.isDateInToday(m.day($0)) }) {
                                let y = (m.mod(m.now) - CGFloat(hr.0 * 60)) / 60 * hh
                                let x = gut + sp + CGFloat(j) * (cw + sp)
                                Rectangle().fill(Color.red).frame(width: cw, height: 2).offset(x: x, y: y - 1)
                                Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: x - 4, y: y - 4)
                            }
                        }
                        .frame(width: g.size.width, height: CGFloat(hr.1 - hr.0) * hh, alignment: .topLeading)
                    }
                    .onAppear { pr.scrollTo(target, anchor: .top) }
                    .onChange(of: open) { _, v in if v { pr.scrollTo(target, anchor: .top) } }
                }
            }
        }
    }
}

// MARK: - 展開後的內容
struct SchedView: View {
    @ObservedObject var m: M
    let open: Bool
    let top: CGFloat
    var onMenu: () -> Void

    var banner: some View {
        HStack {
            if let o = m.live {
                VStack(alignment: .leading, spacing: 2) {
                    Text("● 正在進行").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.orange)
                    Text("\(o.c) \(o.k == "行事曆" ? "" : o.k)").font(.system(size: 14, weight: .bold))
                    Text("\(o.r.isEmpty ? "" : o.r + " · ")\(tma(o.en)) 結束").font(.system(size: 11)).foregroundStyle(.gray)
                }
                Spacer()
                Text("還剩 \(dur(mleft(m.now, o.en)))").font(.system(size: 17, weight: .bold)).foregroundStyle(.orange)
            } else if let o = m.next {
                VStack(alignment: .leading, spacing: 2) {
                    Text("下一個").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.blue)
                    Text("\(o.c) \(o.k == "行事曆" ? "" : o.k)").font(.system(size: 14, weight: .bold))
                    Text("\(dayName(o.st)) \(tma(o.st))\(o.r.isEmpty ? "" : " · " + o.r)").font(.system(size: 11)).foregroundStyle(.gray)
                }
                Spacer()
                Text("\(dur(mleft(m.now, o.st)))後").font(.system(size: 17, weight: .bold)).foregroundStyle(.blue)
            } else {
                Text("最近沒有行程 🎉").font(.system(size: 13)).foregroundStyle(.gray)
                Spacer()
            }
        }
        .lineLimit(1)
        .foregroundStyle(.black)
        .padding(.horizontal, 14).frame(height: 64)
        .background((m.live != nil ? Color.orange : Color.blue).opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
    }

    var list: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(m.snap.cols, id: \.self) { i in
                VStack(spacing: 6) {
                    DayTop(m: m, i: i)
                    ForEach(m.on(i)) { o in Card(o: o, live: m.isLive(o), past: o.en <= m.now) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if m.bad {
                Text("⚠️ 課表檔案格式有誤，先顯示範例（齒輪 → 設定）")
                    .font(.system(size: 11)).foregroundStyle(.red).frame(height: 14)
            }
            banner
            if m.axis {
                AxisGrid(m: m, open: open)
            } else {
                ScrollView(.vertical, showsIndicators: false) { list }
            }
        }
        .padding(.horizontal, 14).padding(.top, top + 8).padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) {
            GearButton(action: onMenu)
                .padding(.top, max((top - 32) / 2, 0)).padding(.trailing, 12)
        }
    }
}
