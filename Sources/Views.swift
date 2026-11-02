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
let wdf = fm("EEE")
func wdName(_ d: Date) -> String { wdf.string(from: d).uppercased() }

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

    var act: Occ? { m.demo ?? (m.wing ? m.soon : nil) }

    var body: some View {
        let o = u.open, a = act, W = m.snap.panelW, H = m.snap.panelH, t = m.theme
        let cw = o ? W : u.nw + (a != nil ? 2 * Root.wingW : 0)
        let shape = NotchShape(w: cw, h: o ? H : u.nh, r: o ? 22 : 10)
        ZStack(alignment: .top) {
            // 背景 + 陰影只畫在形狀上 (便宜)
            shape.fill(o || a == nil ? t.bg : Color.black)
                .shadow(color: .black.opacity(o ? 0.22 : 0), radius: 16, y: 8)
            // 內容一直存在，只用遮罩露出來 -> 打開瞬間不用重建
            SchedView(m: m, open: o, top: u.nh, onMenu: onMenu)
                .frame(width: W, height: H)
                .opacity(o ? 1 : 0)
                .mask(shape)
                .allowsHitTesting(o)
            if let a {
                Wings(o: a, now: m.now, nw: u.nw, nh: u.nh, ac: t.accent)
                    .frame(width: cw, height: u.nh)
                    .opacity(o ? 0 : 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlayPreferenceValue(TourKey.self) { an in
            if o && u.tour != nil {
                TourOverlay(u: u, an: an, W: W, H: H, nw: u.nw, nh: u.nh, t: m.theme)
                    .transition(.opacity)
            }
        }
        .opacity(o || a != nil ? 1 : 0)
        .animation(.spring(duration: 0.42, bounce: 0.16), value: o)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: W)
        .animation(.spring(duration: 0.35, bounce: 0.1), value: H)
        .animation(.easeInOut(duration: 0.3), value: a?.id)
        .animation(.easeInOut(duration: 0.25), value: t)
        .environment(\.colorScheme, t.dark ? .dark : .light)
    }
}

// MARK: - 收起時: 瀏海兩側倒數
struct Wings: View {
    let o: Occ; let now: Date; let nw, nh: CGFloat; let ac: Color
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
                .font(.system(size: 11, weight: .bold)).foregroundStyle(on ? Color.orange : ac)
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
            if !o.isClass {
                Divider()
                HStack(spacing: 12) {
                    Button { hideEvent(o, all: false) } label: { Label("隱藏這次", systemImage: "eye.slash") }
                    Button { hideEvent(o, all: true) } label: { Label("隱藏所有同名", systemImage: "eye.slash.fill") }
                }
                .buttonStyle(.borderless).font(.system(size: 11.5)).foregroundStyle(.secondary)
                Text("可在 設定 → 行事曆 → 已隱藏的活動 恢復").font(.system(size: 10)).foregroundStyle(.tertiary)
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
        .tour("card")
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
        .tour("card")
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

// MARK: - 現在的位置
struct NowDot: View {
    var body: some View {
        Circle().fill(Color.red).frame(width: 10, height: 10)
            .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
            .phaseAnimator([false, true]) { v, on in
                v.shadow(color: .red.opacity(on ? 0.9 : 0.2), radius: on ? 6 : 2)
            } animation: { _ in .easeInOut(duration: 1.0) }
    }
}
struct NowRow: View {
    let now: Date
    var body: some View {
        HStack(spacing: 4) {
            NowDot()
            Text("現在 \(tf.string(from: now))").font(.system(size: 9.5, weight: .bold)).foregroundStyle(.red)
            Rectangle().fill(Color.red).frame(height: 2)
        }
        .frame(height: 14)
    }
}

// MARK: - 「+N 個」: 點開看全部全天活動
struct MoreChip: View {
    let list: [Occ]
    @State var pop = false
    var body: some View {
        Text("+\(list.count - M.chipMax) 個")
            .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(pop ? 0.1 : 0.04)))
            .contentShape(Rectangle())
            .onTapGesture { pop = true }
            .popover(isPresented: $pop, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("全天 / 跨日活動").font(.headline)
                    ForEach(list) { o in
                        HStack(spacing: 8) {
                            RoundedRectangle(cornerRadius: 2).fill(o.col).frame(width: 4, height: 16)
                            Text(o.c).lineLimit(1)
                            Spacer()
                            Button { hideEvent(o, all: true) } label: { Image(systemName: "eye.slash") }
                                .buttonStyle(.borderless).foregroundStyle(.secondary).help("隱藏所有同名活動")
                        }
                        .font(.system(size: 12))
                    }
                }
                .padding(14).frame(width: 280)
            }
    }
}

// MARK: - 圓形圖示按鈕 (齒輪、換週)
struct IconBtn: View {
    let icon: String; let t: Theme
    var size: CGFloat = 13
    var help = ""
    var disabled = false
    var action: () -> Void
    @State var hov = false
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(disabled ? t.sub.opacity(0.4) : hov ? t.fg : t.sub)
            .frame(width: 30, height: 30)
            .background(Circle().fill(t.fg.opacity(hov && !disabled ? 0.1 : 0.05)))
            .contentShape(Circle())
            .onHover { hov = $0 }
            .onTapGesture { if !disabled { action() } }
            .help(help)
    }
}

// MARK: - 每一欄的標題 (+ 全天/跨日事件，最多 3 個)
struct DayTop: View {
    @ObservedObject var m: M
    let i: Int
    var body: some View {
        let d = m.day(i), list = m.allOn(i)
        VStack(spacing: 2) {
            Text("\(wdName(d)) \(df.string(from: d))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Calendar.current.isDateInToday(d) ? m.theme.accent : m.theme.sub)
                .frame(height: 18)
            ForEach(list.prefix(M.chipMax)) { o in AllDayChip(o: o).frame(height: M.chipH - 2) }
            if list.count > M.chipMax {
                MoreChip(list: list).frame(height: M.chipH - 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .tour("header")
    }
}

// MARK: - 時間軸 (可捲動，打開時自動捲到現在)
struct AxisGrid: View {
    @ObservedObject var m: M
    let open: Bool
    let gut: CGFloat = 34, sp: CGFloat = 6, pad: CGFloat = 8     // pad: 讓最上面的時間數字不被切掉

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
                VStack(spacing: 0) {
                    Color.clear.frame(height: 20)
                    if m.snap.allMax > 0 { Text("全天").font(.system(size: 9)).foregroundStyle(m.theme.sub) }
                }
                .frame(width: gut)
                ForEach(cs, id: \.self) { i in DayTop(m: m, i: i) }
            }
            GeometryReader { g in
                let cw = (g.size.width - gut - sp * CGFloat(cs.count)) / CGFloat(cs.count)
                ScrollViewReader { pr in
                    ScrollView(.vertical, showsIndicators: false) {
                        ZStack(alignment: .topLeading) {
                            VStack(spacing: 0) {
                                Color.clear.frame(height: pad)
                                ForEach(hr.0..<hr.1, id: \.self) { h in
                                    HStack(alignment: .top, spacing: 0) {
                                        Text(h == 12 ? "12" : "\(h % 12)").font(.system(size: 9)).foregroundStyle(m.theme.sub)
                                            .frame(width: gut, alignment: .leading).offset(y: -5)
                                        Rectangle().fill(m.theme.line).frame(height: 1)
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
                                    let y = (m.mod(o.st) - CGFloat(hr.0 * 60)) / 60 * hh + pad
                                    let h = max(CGFloat(o.en.timeIntervalSince(o.st)) / 3600 * hh - 1, 15)
                                    MiniCard(o: o, live: m.isLive(o), past: o.en <= m.now)
                                        .frame(width: w - 1, height: h)
                                        .offset(x: x0 + CGFloat(ln.i) * w, y: y)
                                }
                            }
                            // 「現在在這裡」: 整排淡紅線 + 今天那欄粗紅線 + 左邊時間標籤
                            if let j = cs.firstIndex(where: { Calendar.current.isDateInToday(m.day($0)) }) {
                                let y = (m.mod(m.now) - CGFloat(hr.0 * 60)) / 60 * hh + pad
                                let x = gut + sp + CGFloat(j) * (cw + sp)
                                Rectangle().fill(Color.red.opacity(0.3)).frame(width: g.size.width - gut - sp, height: 1)
                                    .offset(x: gut + sp, y: y - 0.5)
                                Rectangle().fill(Color.red).frame(width: cw, height: 2.5).offset(x: x, y: y - 1.25)
                                NowDot().offset(x: x - 5, y: y - 5)
                                Text(tf.string(from: m.now))
                                    .font(.system(size: 9.5, weight: .bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 4).padding(.vertical, 1.5)
                                    .background(Capsule().fill(Color.red))
                                    .frame(width: gut + 2, alignment: .leading)
                                    .offset(x: -2, y: y - 7)
                            }
                        }
                        .frame(width: g.size.width, height: CGFloat(hr.1 - hr.0) * hh + pad * 2, alignment: .topLeading)
                    }
                    .onAppear { pr.scrollTo(target, anchor: .top) }
                    .onChange(of: open) { _, v in if v { pr.scrollTo(target, anchor: .top) } }
                }
            }
            .tour("grid")
        }
    }
}

// MARK: - 展開後的內容
struct SchedView: View {
    @ObservedObject var m: M
    let open: Bool
    let top: CGFloat
    var onMenu: () -> Void

    var weekLabel: String {
        let tag = [0: "本週", 1: "下週", -1: "上週", 2: "下下週"][m.wkOff] ?? ""
        return "\(df.string(from: m.day(0))) – \(df.string(from: m.day(6)))  ·  \(tag)"
    }

    // 上方工具列: 週次 + 換週 + 齒輪 (在選單列下面，不會太貼頂)
    var toolbar: some View {
        let t = m.theme
        return HStack(spacing: 6) {
            Text(weekLabel).font(.system(size: 13, weight: .semibold)).foregroundStyle(t.fg)
            if m.wkOff != 0 {
                Text("回到本週").font(.system(size: 11, weight: .medium)).foregroundStyle(t.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(t.accent.opacity(0.12)))
                    .onTapGesture { m.wkOff = 0; m.derive() }
            }
            Spacer()
            IconBtn(icon: "chevron.left", t: t, help: "上一週", disabled: m.wkOff <= -1) { m.shift(-1) }
            IconBtn(icon: "chevron.right", t: t, help: "下一週", disabled: m.wkOff >= 2) { m.shift(1) }
            IconBtn(icon: t.dark ? "sun.max.fill" : "moon.fill", t: t, help: t.dark ? "切換成淺色" : "切換成深色") {
                UserDefaults.standard.set(t.dark ? 1 : 2, forKey: "appearance")
                m.derive()
            }
            .padding(.leading, 4)
            IconBtn(icon: "gearshape.fill", t: t, size: 14, help: "設定", action: onMenu)
                .tour("gear")
                .padding(.leading, 4)
        }
        .frame(height: 30)
    }

    var banner: some View {
        let t = m.theme
        return HStack {
            if let o = m.live {
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.isClass ? "● 上課中" : "● 進行中").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.orange)
                    Text("\(o.c) \(o.k == "行事曆" ? "" : o.k)").font(.system(size: 14, weight: .bold))
                    Text("\(o.r.isEmpty ? "" : o.r + " · ")\(tma(o.en)) 結束").font(.system(size: 11)).foregroundStyle(t.sub)
                }
                Spacer()
                Text("還剩 \(dur(mleft(m.now, o.en)))").font(.system(size: 17, weight: .bold)).foregroundStyle(.orange)
            } else if let o = m.next {
                VStack(alignment: .leading, spacing: 2) {
                    Text(o.isClass ? "下一堂課" : "下一個行程").font(.system(size: 10.5, weight: .bold)).foregroundStyle(t.accent)
                    Text("\(o.c) \(o.k == "行事曆" ? "" : o.k)").font(.system(size: 14, weight: .bold))
                    Text("\(dayName(o.st)) \(tma(o.st))\(o.r.isEmpty ? "" : " · " + o.r)").font(.system(size: 11)).foregroundStyle(t.sub)
                }
                Spacer()
                Text("\(dur(mleft(m.now, o.st)))後").font(.system(size: 17, weight: .bold)).foregroundStyle(t.accent)
            } else {
                Text("最近沒有課 🎉").font(.system(size: 13)).foregroundStyle(t.sub)
                Spacer()
            }
        }
        .lineLimit(1)
        .foregroundStyle(t.fg)
        .padding(.horizontal, 14).frame(height: 64)
        .background((m.live != nil ? Color.orange : t.accent).opacity(t.dark ? 0.16 : 0.09), in: RoundedRectangle(cornerRadius: 12))
        .tour("banner")
    }

    var list: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(m.snap.cols, id: \.self) { i in
                let list = m.on(i), today = Calendar.current.isDateInToday(m.day(i))
                let cut = list.firstIndex { $0.en > m.now } ?? list.count      // 「現在」插在這張卡片前面
                VStack(spacing: 6) {
                    DayTop(m: m, i: i)
                    ForEach(Array(list.enumerated()), id: \.element.id) { k, o in
                        if today && k == cut { NowRow(now: m.now) }
                        Card(o: o, live: m.isLive(o), past: o.en <= m.now)
                    }
                    if today && cut == list.count { NowRow(now: m.now) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            toolbar
            if m.bad {
                Text("⚠️ 課表檔案格式有誤，先顯示範例（齒輪 → 設定）")
                    .font(.system(size: 11)).foregroundStyle(.red).frame(height: 14)
            }
            banner.padding(.bottom, 2)
            if m.axis {
                AxisGrid(m: m, open: open)
            } else {
                ScrollView(.vertical, showsIndicators: false) { list }.tour("grid")
            }
        }
        .padding(.horizontal, 16).padding(.top, top + 8).padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
