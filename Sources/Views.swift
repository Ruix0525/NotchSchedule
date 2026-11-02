import SwiftUI
import AppKit

func fm(_ s: String) -> DateFormatter { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = s; return f }
let tf = fm("h:mm"), af = fm("a"), df = fm("M/d")
func tma(_ d: Date) -> String { "\(tf.string(from: d)) \(af.string(from: d))" }
func mleft(_ a: Date, _ b: Date) -> Int { Int(ceil(b.timeIntervalSince(a) / 60)) }

func dur(_ m: Int) -> String {                               // 分鐘 -> "2 小時 15 分鐘"
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

let wd = ["MON", "TUE", "WED", "THU", "FRI"]
func dayHeader(_ m: M, _ i: Int) -> some View {
    let d = m.day(i)
    return Text("\(wd[i]) \(df.string(from: d))")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(Calendar.current.isDateInToday(d) ? Color.orange : Color.black.opacity(0.6))
        .frame(maxWidth: .infinity)
}

func openURL(_ o: Occ) { if let s = o.url, let u = URL(string: s) { NSWorkspace.shared.open(u) } }
func tip(_ o: Occ) -> String { "\(o.c) \(o.n)\n\(o.k) · \(tma(o.st)) – \(tma(o.en))\(o.r.isEmpty ? "" : "\n" + o.r)" }

// MARK: - 根視圖: 從瀏海長出來的面板
struct Root: View {
    @ObservedObject var m: M
    @ObservedObject var u: UI
    let W: CGFloat, H: CGFloat
    var onMenu: () -> Void
    static let wingW: CGFloat = 96                           // 倒數兩翼寬度

    var act: Occ? { m.wing ? m.soon : nil }

    var body: some View {
        let o = u.open, a = act
        ZStack(alignment: .top) {
            if o {
                SchedView(m: m, top: u.nh, onMenu: onMenu)
                    .frame(width: W, height: H)
                    .transition(.opacity)
            } else if let a {
                Wings(o: a, now: m.now, nw: u.nw, nh: u.nh)
                    .transition(.opacity)
            }
        }
        .frame(width: o ? W : u.nw + (a != nil ? 2 * Root.wingW : 0), height: o ? H : u.nh, alignment: .top)
        .background(o || a == nil ? Color.white : Color.black)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: o ? 20 : 10, bottomTrailingRadius: o ? 20 : 10))
        .shadow(color: .black.opacity(o ? 0.22 : 0), radius: 14, y: 6)
        .opacity(o || a != nil ? 1 : 0)                      // 沒事時完全隱形
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: o)
        .animation(.easeInOut(duration: 0.3), value: a?.id)
        .environment(\.colorScheme, .light)
    }
}

// MARK: - 收起時: 瀏海兩側的倒數
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

// MARK: - 列表模式卡片
struct Card: View {
    let o: Occ; let live, past: Bool
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
        .onTapGesture { openURL(o) }
        .help(tip(o))
    }
}

// MARK: - 時間軸模式卡片
struct MiniCard: View {
    let o: Occ; let live, past: Bool
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
        .onTapGesture { openURL(o) }
        .help(tip(o))
    }
}

// MARK: - 時間軸 (卡片高度 = 上課時間長度，紅線 = 現在)
struct AxisGrid: View {
    @ObservedObject var m: M
    let gut: CGFloat = 22, sp: CGFloat = 6

    var body: some View {
        let hr = m.hours
        VStack(spacing: 4) {
            HStack(spacing: sp) {
                Color.clear.frame(width: gut, height: 1)
                ForEach(0..<5, id: \.self) { i in dayHeader(m, i) }
            }
            GeometryReader { g in
                let hh = g.size.height / CGFloat(hr.1 - hr.0)
                let cw = (g.size.width - gut - sp * 5) / 5
                ZStack(alignment: .topLeading) {
                    ForEach(hr.0...hr.1, id: \.self) { h in
                        Rectangle().fill(Color.black.opacity(0.07)).frame(height: 1)
                            .offset(y: CGFloat(h - hr.0) * hh)
                        Text(h == 12 ? "12" : "\(h % 12)").font(.system(size: 9)).foregroundStyle(.gray)
                            .offset(y: CGFloat(h - hr.0) * hh - 5)
                    }
                    ForEach(0..<5, id: \.self) { i in
                        let x = gut + sp + CGFloat(i) * (cw + sp)
                        ForEach(m.on(m.day(i))) { o in
                            let y = (m.mod(o.st) - CGFloat(hr.0 * 60)) / 60 * hh
                            let h = max(CGFloat(o.en.timeIntervalSince(o.st)) / 3600 * hh - 1, 16)
                            MiniCard(o: o, live: m.isLive(o), past: o.en <= m.now)
                                .frame(width: cw, height: h)
                                .offset(x: x, y: y)
                        }
                    }
                    if let i = (0..<5).first(where: { Calendar.current.isDateInToday(m.day($0)) }) {
                        let y = (m.mod(m.now) - CGFloat(hr.0 * 60)) / 60 * hh
                        let x = gut + sp + CGFloat(i) * (cw + sp)
                        if y >= 0 && y <= g.size.height {
                            Rectangle().fill(Color.red).frame(width: cw, height: 2).offset(x: x, y: y - 1)
                            Circle().fill(Color.red).frame(width: 8, height: 8).offset(x: x - 4, y: y - 4)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 展開後的內容
struct SchedView: View {
    @ObservedObject var m: M
    let top: CGFloat
    var onMenu: () -> Void

    var banner: some View {
        HStack {
            if let o = m.live {
                VStack(alignment: .leading, spacing: 2) {
                    Text("● 正在上課").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.orange)
                    Text("\(o.c) \(o.k)").font(.system(size: 14, weight: .bold))
                    Text("\(o.r.isEmpty ? "" : o.r + " · ")\(tma(o.en)) 下課").font(.system(size: 11)).foregroundStyle(.gray)
                }
                Spacer()
                Text("還剩 \(dur(mleft(m.now, o.en)))").font(.system(size: 17, weight: .bold)).foregroundStyle(.orange)
            } else if let o = m.next {
                VStack(alignment: .leading, spacing: 2) {
                    Text("下一堂").font(.system(size: 10.5, weight: .bold)).foregroundStyle(.blue)
                    Text("\(o.c) \(o.k)").font(.system(size: 14, weight: .bold))
                    Text("\(dayName(o.st)) \(tma(o.st))\(o.r.isEmpty ? "" : " · " + o.r)").font(.system(size: 11)).foregroundStyle(.gray)
                }
                Spacer()
                Text("\(dur(mleft(m.now, o.st)))後").font(.system(size: 17, weight: .bold)).foregroundStyle(.blue)
            } else {
                Text("這兩週沒有課 🎉").font(.system(size: 13)).foregroundStyle(.gray)
                Spacer()
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background((m.live != nil ? Color.orange : Color.blue).opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    var list: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(0..<5, id: \.self) { i in
                VStack(spacing: 6) {
                    dayHeader(m, i)
                    ForEach(m.on(m.day(i))) { o in Card(o: o, live: m.isLive(o), past: o.en <= m.now) }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if m.bad {
                Text("⚠️ schedule.json 格式有誤，先顯示範例課表（齒輪 → 編輯課表）")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }
            banner
            if m.axis {
                AxisGrid(m: m)
            } else {
                list
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14).padding(.top, top + 8).padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay(alignment: .topTrailing) {
            Button { onMenu() } label: { Image(systemName: "gearshape.fill").font(.system(size: 13)) }
                .buttonStyle(.plain).foregroundStyle(.gray)
                .padding(.top, 8).padding(.trailing, 18)
        }
    }
}
