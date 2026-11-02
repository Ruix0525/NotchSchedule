import SwiftUI

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

let zh = ["日", "一", "二", "三", "四", "五", "六"]
func dayName(_ d: Date) -> String {
    let c = Calendar.current
    if c.isDateInToday(d) { return "今天" }
    if c.isDateInTomorrow(d) { return "明天" }
    return "週" + zh[c.component(.weekday, from: d) - 1]
}

// MARK: - 卡片
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
    }
}

// MARK: - 整週面板
struct SchedView: View {
    @ObservedObject var m: M
    let top: CGFloat
    var onMenu: () -> Void = {}
    let wd = ["MON", "TUE", "WED", "THU", "FRI"]

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
                Text("這兩週沒有課").font(.system(size: 13)).foregroundStyle(.gray)
                Spacer()
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background((m.live != nil ? Color.orange : Color.blue).opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }

    var body: some View {
        VStack(spacing: 12) {
            if m.bad {
                Text("⚠️ schedule.json 格式有誤，先顯示範例課表（選單列 → 編輯課表）")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }
            banner
            HStack(alignment: .top, spacing: 8) {
                ForEach(0..<5, id: \.self) { i in
                    let d = m.day(i)
                    VStack(spacing: 6) {
                        Text("\(wd[i]) \(df.string(from: d))")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Calendar.current.isDateInToday(d) ? Color.orange : Color.black.opacity(0.6))
                        ForEach(m.on(d)) { o in
                            Card(o: o, live: o.st <= m.now && m.now < o.en, past: o.en <= m.now)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.top, top + 8).padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(.white)
        .overlay(alignment: .topTrailing) {                    // 齒輪: 打開設定選單
            Button { onMenu() } label: { Image(systemName: "gearshape.fill").font(.system(size: 13)) }
                .buttonStyle(.plain).foregroundStyle(.gray)
                .padding(.top, 8).padding(.trailing, 18)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 20, bottomTrailingRadius: 20))
        .environment(\.colorScheme, .light)
    }
}
