// 新手教學: 聚光燈 (會移動) + 固定位置的說明卡
import SwiftUI

struct TourStep { let id, icon, title, text: String }

let tourSteps: [TourStep] = [
    TourStep(id: "notch", icon: "hand.point.up.left.fill", title: "從瀏海打開",
             text: "把滑鼠移到瀏海停一下，課表就會從這裡長出來；移開就自動收起。上課前 15 分鐘，瀏海兩側還會顯示倒數（設定 → 一般 → 預覽 可以先看效果）。"),
    TourStep(id: "banner", icon: "bell.badge.fill", title: "下一堂課",
             text: "這裡永遠告訴你：現在在上什麼課、或下一堂課是什麼時候、在哪裡、還有多久。"),
    TourStep(id: "header", icon: "sun.max.fill", title: "全天活動",
             text: "每天日期下面的小色條是「全天」或「跨好幾天」的行事曆活動，例如節日、限時活動。太多的話會收成「+N 個」，點一下就能展開。"),
    TourStep(id: "grid", icon: "calendar", title: "整週課表",
             text: "課表和 Google 行事曆的活動都在這裡。時間重疊的會並排，紅線是現在時間，已經結束的會變淡。"),
    TourStep(id: "card", icon: "cursorarrow.click.2", title: "點卡片看詳情",
             text: "點任何一張卡片可以看時間、地點、備註和連結。不想看到的行事曆活動，可以在這裡「隱藏這次」或「隱藏所有同名活動」。"),
    TourStep(id: "gear", icon: "gearshape.fill", title: "換週與設定",
             text: "旁邊的箭頭可以看上一週和下一週。齒輪打開設定：編輯課表、選擇日曆、換主題色、抓學校行事曆、設定上課前提醒。"),
    TourStep(id: "done", icon: "checkmark.seal.fill", title: "準備好了！",
             text: "之後想再看一次，到「設定 → 一般 → 重播新手教學」就可以。"),
]

// 讓畫面元件回報自己的位置
struct TourKey: PreferenceKey {
    static var defaultValue: [String: [Anchor<CGRect>]] = [:]
    static func reduce(value: inout [String: [Anchor<CGRect>]], nextValue: () -> [String: [Anchor<CGRect>]]) {
        value.merge(nextValue()) { $0 + $1 }
    }
}
extension View {
    func tour(_ id: String) -> some View { anchorPreference(key: TourKey.self, value: .bounds) { [id: [$0]] } }
}

// 整片變暗，只挖出一個圓角洞
struct Spot: Shape {
    var r: CGRect
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(r.origin.x, r.origin.y), AnimatablePair(r.size.width, r.size.height)) }
        set { r = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first, height: newValue.second.second) }
    }
    func path(in rect: CGRect) -> Path {
        var p = Path(rect)
        p.addRoundedRect(in: r, cornerSize: CGSize(width: 12, height: 12))
        return p
    }
}

struct TourOverlay: View {
    @ObservedObject var u: UI
    let an: [String: [Anchor<CGRect>]]
    let W, H, nw, nh: CGFloat
    let t: Theme

    func rect(_ g: GeometryProxy, _ id: String, _ panel: CGRect) -> CGRect {
        if id == "notch" { return CGRect(x: g.size.width / 2 - nw / 2 - 10, y: -6, width: nw + 20, height: nh + 12) }
        if id == "done" { return CGRect(x: panel.midX, y: panel.midY, width: 0, height: 0) }
        guard let list = an[id], !list.isEmpty else { return panel.insetBy(dx: 12, dy: 12) }
        let rs = id == "card" ? [g[list[0]]] : list.map { g[$0] }
        let un = rs.dropFirst().reduce(rs[0]) { $0.union($1) }.insetBy(dx: -6, dy: -6)
        let c = un.intersection(panel.insetBy(dx: 4, dy: 4))
        return c.isNull || c.isEmpty ? panel.insetBy(dx: 12, dy: 12) : c
    }

    var body: some View {
        GeometryReader { g in
            let st = u.tour ?? 0, step = tourSteps[st]
            let panel = CGRect(x: g.size.width / 2 - W / 2, y: 0, width: W, height: H)
            let r = rect(g, step.id, panel)
            let below = H + 190 < g.size.height                     // 說明卡放面板下方 (放得下的話)
            let cardY = below ? H + 100 : H - 100
            let tagAbove = r.minY > 60
            ZStack {
                // 1. 變暗 + 挖洞 (洞會滑到下一個位置)
                Spot(r: r)
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .mask(NotchShape(w: W, h: H, r: 22))
                    .contentShape(Rectangle())
                    .onTapGesture { }                                // 擋住後面的點擊
                // 2. 發光外框 (會呼吸)
                if step.id != "done" {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(t.accent, lineWidth: 2.5)
                        .shadow(color: t.accent.opacity(0.8), radius: 10)
                        .frame(width: r.width, height: r.height)
                        .phaseAnimator([false, true]) { v, on in
                            v.scaleEffect(on ? 1.025 : 1).opacity(on ? 0.55 : 1)
                        } animation: { _ in .easeInOut(duration: 0.9) }
                        .position(x: r.midX, y: r.midY)
                        .allowsHitTesting(false)
                    // 3. 跟著洞跑的小標籤
                    Label(step.title, systemImage: step.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(t.accent))
                        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
                        .position(x: min(max(r.midX, panel.minX + 90), panel.maxX - 90),
                                  y: tagAbove ? r.minY - 18 : r.maxY + 18)
                        .allowsHitTesting(false)
                }
                // 4. 固定位置的說明卡
                TourCard(u: u, st: st, t: t)
                    .position(x: g.size.width / 2, y: cardY)
            }
            .animation(.spring(duration: 0.55, bounce: 0.2), value: st)
        }
    }
}

struct TourCard: View {
    @ObservedObject var u: UI
    let st: Int
    let t: Theme
    var body: some View {
        let step = tourSteps[st], last = st == tourSteps.count - 1, ac = t.accent
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: step.icon).font(.system(size: 18)).foregroundStyle(ac)
                    .frame(width: 34, height: 34).background(Circle().fill(ac.opacity(0.14)))
                VStack(alignment: .leading, spacing: 1) {
                    Text("新手教學 \(st + 1) / \(tourSteps.count)").font(.system(size: 10.5)).foregroundStyle(.secondary)
                    Text(step.title).font(.system(size: 15, weight: .bold))
                }
                Spacer()
                if !last { Button("跳過") { u.endTour() }.buttonStyle(.borderless).foregroundStyle(.secondary) }
            }
            Text(step.text).font(.system(size: 12.5)).foregroundStyle(.primary.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                .id(st).transition(.opacity)
            HStack {
                HStack(spacing: 5) {
                    ForEach(0..<tourSteps.count, id: \.self) { i in
                        Capsule().fill(i == st ? ac : Color.secondary.opacity(0.3))
                            .frame(width: i == st ? 16 : 6, height: 6)
                    }
                }
                Spacer()
                if st > 0 { Button("上一步") { u.tour = st - 1 }.buttonStyle(.bordered) }
                Button(last ? "開始使用" : "下一步") { if last { u.endTour() } else { u.tour = st + 1 } }
                    .buttonStyle(.borderedProminent).tint(ac).keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 440)
        .background(RoundedRectangle(cornerRadius: 16).fill(t.bg))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(t.fg.opacity(0.08)))
        .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
    }
}
