// 瀏海偵測、選單、上課前提醒、設定視窗
import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement

// 一直掛在螢幕頂端的透明面板，收起時滑鼠可以穿透
final class Panel: NSPanel {
    init(_ v: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear; isOpaque = false; hasShadow = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = v
    }
    override var canBecomeKey: Bool { true }
}

final class AD: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let m = M(), u = UI(), store = Store(), ud = UserDefaults.standard
    var p: Panel!, sw: NSWindow?, si: NSStatusItem!, t: Timer?, t2: Timer?
    var entered = false, holdUntil: Date?, hoverAt: Date?, outAt: Date?
    var menu = NSMenu()
    var sent = Set<String>()
    var lastSig = ""
    let maxW: CGFloat = 920, pad: CGFloat = 30
    var maxH: CGFloat { (scr.frame.height * 0.82).rounded() }

    var scr: NSScreen { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main! }
    var nw: CGFloat {
        let s = scr
        if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea { return s.frame.width - l.width - r.width }
        return 200
    }
    var nh: CGFloat { max(scr.safeAreaInsets.top, 24) }
    var zone: NSRect {
        let f = scr.frame, w = nw + (m.wing && m.soon != nil ? 2 * Root.wingW : 0)
        return NSRect(x: f.midX - w / 2, y: f.maxY - nh, width: w, height: nh + 2)
    }
    var full: NSRect {
        let f = scr.frame, w = m.snap.panelW, h = m.snap.panelH
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h)
    }

    func place() {
        let f = scr.frame
        u.nw = nw; u.nh = nh; m.nh = nh; m.maxH = maxH
        p.setFrame(NSRect(x: f.midX - maxW / 2 - pad, y: f.maxY - maxH - pad, width: maxW + 2 * pad, height: maxH + pad), display: true)
        m.derive()
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        ud.register(defaults: ["lead": 10, "pop": true, "noti": true, "cal": false, "allday": true, "axis": false, "wing": true, "evRemind": false, "weekStart": 0, "weekend": true, "schoolShow": true, "schoolAuto": true, "autoUpdate": true, "autoInstall": true])
        NSApp.setActivationPolicy(.accessory)
        store.onSave = { [weak self] in self?.m.reloadSoon() }
        p = Panel(NSHostingView(rootView: Root(m: m, u: u, onMenu: { [weak self] in self?.popMenu() })))
        p.ignoresMouseEvents = true
        place()
        p.orderFrontRegardless()
        m.reload()
        lastSig = sig()
        u.onTourEnd = { [weak self] in
            guard let self else { return }
            self.ud.set(true, forKey: "tourDone")
            self.holdUntil = Date().addingTimeInterval(2); self.entered = false
        }
        NotificationCenter.default.addObserver(forName: .nsTour, object: nil, queue: .main) { [weak self] _ in
            self?.sw?.orderOut(nil); self?.startTour()
        }
        NotificationCenter.default.addObserver(forName: .nsDemo, object: nil, queue: .main) { [weak self] _ in self?.demoWings() }
        NotificationCenter.default.addObserver(forName: .nsUpdate, object: nil, queue: .main) { [weak self] _ in self?.doUpdate() }
        NotificationCenter.default.addObserver(forName: .nsCheckUpdate, object: nil, queue: .main) { [weak self] _ in self?.checkUpdate(manual: true) }
        NotificationCenter.default.addObserver(forName: .nsDemoRemind, object: nil, queue: .main) { [weak self] _ in self?.demoRemind() }
        // 系統切換淺色/深色 -> 主題跟著換
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                                                            object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.m.derive() }
        }
        if !ud.bool(forKey: "tourDone") {                       // 第一次開: 自動教學
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.startTour() }
        }
        let nc0 = NotificationCenter.default
        nc0.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.place() }
        // 只有「我們的」設定真的變了才重新整理 (系統常常會發這個通知)
        nc0.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            let s = self.sig()
            if s != self.lastSig { self.lastSig = s; self.m.reloadSoon(); self.buildMenu() }
        }
        buildMenu()
        let nc = UNUserNotificationCenter.current(); nc.delegate = self
        if ud.bool(forKey: "noti") { nc.requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        t = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        t2 = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.m.tick(); self?.remind(); self?.autoSchool(); self?.checkUpdate()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.autoSchool() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkUpdate() }
        if ud.bool(forKey: "justUpdated") {                          // 剛自動更新完 -> 通知一下
            ud.set(false, forKey: "justUpdated")
            let c = UNMutableNotificationContent()
            c.title = "NotchSchedule 已更新到 v\(Updater.current)"
            c.body = "新功能已經可以用了 🎉"
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "updated", content: c, trigger: nil))
        }
        remind()
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) { h([.banner, .sound]) }

    // MARK: 滑鼠
    func tick() {
        let ms = NSEvent.mouseLocation
        if u.tour != nil { return }                              // 教學中不自動收起
        if !u.open {
            if zone.contains(ms) {
                if hoverAt == nil { hoverAt = Date() }
                else if Date().timeIntervalSince(hoverAt!) > 0.12 { show() }
            } else { hoverAt = nil }
            return
        }
        // 滑鼠在面板、或在面板跳出的小視窗 (詳細資訊、選單) 上 -> 不收
        let onPop = NSApp.windows.contains { $0 !== p && $0 !== sw && $0.isVisible && $0.frame.insetBy(dx: -8, dy: -8).contains(ms) }
        if onPop || full.insetBy(dx: -12, dy: -12).contains(ms) { entered = true; outAt = nil; return }
        if let h = holdUntil, !entered, Date() < h { return }
        if outAt == nil { outAt = Date() }
        else if Date().timeIntervalSince(outAt!) > 0.3 { hide() }
    }

    func show(hold: TimeInterval? = nil) {
        holdUntil = hold.map { Date().addingTimeInterval($0) }
        entered = false; outAt = nil; hoverAt = nil
        if u.open { return }
        m.tick()
        p.ignoresMouseEvents = false
        u.open = true
    }

    func hide() {
        u.open = false
        if m.wkOff != 0 { m.wkOff = 0; m.derive() }            // 下次打開回到本週
        p.ignoresMouseEvents = true
        hoverAt = nil; outAt = nil
    }

    // 倒數預覽: 先「8 分後」再「剩 25 分」
    func sample(_ st: Date, _ en: Date) -> Occ {
        let s = m.occs.first { $0.isClass }
        return Occ(id: "demo-\(Int(st.timeIntervalSince1970))", st: st, en: en, c: s?.c ?? "PHYS 2201", n: s?.n ?? "",
                   k: s?.k ?? "Lecture", r: s?.r ?? "Tate Hall 105", col: s?.col ?? Color(hex: "#E0E680"), isClass: true)
    }
    func demoWings() {
        hide(); m.tick()
        let n = Date()
        m.demo = sample(n.addingTimeInterval(8 * 60), n.addingTimeInterval(58 * 60))
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { [weak self] in
            self?.m.demo = self?.sample(n.addingTimeInterval(-25 * 60), n.addingTimeInterval(25 * 60))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 7) { [weak self] in self?.m.demo = nil }
    }
    func demoRemind() {
        let o = sample(Date().addingTimeInterval(Double(max(ud.integer(forKey: "lead"), 1)) * 60), Date().addingTimeInterval(3600))
        if ud.bool(forKey: "noti") {
            let c = UNMutableNotificationContent()
            c.title = "（預覽）\(ud.integer(forKey: "lead")) 分鐘後：\(o.c) \(o.k)"
            c.body = "\(tma(o.st)) – \(tma(o.en)) · \(o.r)"
            c.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: o.id, content: c, trigger: nil))
        }
        if ud.bool(forKey: "pop") { show(hold: 5) }
    }

    // MARK: 自動更新 (每 6 小時檢查一次 GitHub Releases)
    func checkUpdate(manual: Bool = false) {
        guard manual || ud.bool(forKey: "autoUpdate") else { return }
        if !manual && Date().timeIntervalSince1970 - ud.double(forKey: "updChecked") < 6 * 3600 { return }
        ud.set(Date().timeIntervalSince1970, forKey: "updChecked")
        Task {
            let r = await Updater.check()
            await MainActor.run {
                self.u.newVer = r?.0; self.u.newURL = r?.1
                self.buildMenu()
                if manual && r == nil { self.alert("已經是最新版", "目前版本 v\(Updater.current)") }
                else if manual, let v = r?.0 { self.ask(v) }
                else if r != nil && self.ud.bool(forKey: "autoInstall") && !self.u.open && self.sw?.isVisible != true {
                    self.doUpdate()                                  // 沒在用的時候自動裝
                }
            }
        }
    }
    func ask(_ v: String) {
        let a = NSAlert()
        a.messageText = "有新版 v\(v)"
        a.informativeText = "目前是 v\(Updater.current)。要現在更新嗎？App 會自動重新打開。"
        a.addButton(withTitle: "更新"); a.addButton(withTitle: "稍後")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { doUpdate() }
    }
    func alert(_ title: String, _ message: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = message
        a.addButton(withTitle: "好")
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
    func doUpdate() {
        guard let url = u.newURL, !u.updating else { return }
        u.updating = true
        Task {
            do { try await Updater.install(url) }
            catch {
                await MainActor.run {
                    self.u.updating = false
                    self.alert("更新失敗", error.localizedDescription + "\n可以到 GitHub 手動下載最新版。")
                }
            }
        }
    }
    @objc func updateMenu() { if u.newVer != nil { doUpdate() } else { checkUpdate(manual: true) } }

    // 每週自動從 UMN 更新一次學校行事曆
    var fetchingSchool = false
    func autoSchool() {
        guard ud.bool(forKey: "schoolAuto"), !fetchingSchool else { return }
        if Date().timeIntervalSince1970 - ud.double(forKey: "schoolFetched") < 7 * 86400 { return }
        fetchingSchool = true
        Task {
            let r = try? await UMN.fetchAll()
            await MainActor.run {
                if let r { saveSchool(r); self.m.reloadSoon() }
                else { self.ud.set(Date().timeIntervalSince1970 - 6 * 86400, forKey: "schoolFetched") }  // 失敗: 一天後再試
                self.fetchingSchool = false
            }
        }
    }

    func startTour() {
        u.tour = 0
        show(hold: 3600)
    }

    func sig() -> String {
        ["lead", "pop", "noti", "cal", "allday", "axis", "wing", "evRemind", "hiddenCals", "hiddenTitles", "hiddenIds",
         "appearance", "accent", "weekStart", "weekend", "schoolShow"]
            .map { "\(ud.object(forKey: $0) ?? "-")" }.joined(separator: "|")
    }

    // MARK: 開始前提醒
    func remind() {
        let lead = ud.integer(forKey: "lead"); guard lead > 0 else { return }
        for o in m.foc where !sent.contains(o.id) {
            let x = o.st.timeIntervalSinceNow
            guard x > 0 && x <= Double(lead * 60) else { continue }
            sent.insert(o.id)
            if ud.bool(forKey: "pop") { show(hold: 10) }
            if ud.bool(forKey: "noti") {
                let c = UNMutableNotificationContent()
                c.title = "\(dur(Int(ceil(x / 60))))後：\(o.c)\(o.k == "行事曆" ? "" : " " + o.k)"
                c.body = "\(tma(o.st)) – \(tma(o.en))\(o.r.isEmpty ? "" : " · " + o.r)"
                c.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: o.id, content: c, trigger: nil))
            }
        }
    }

    // MARK: 設定視窗
    @objc func openSettings() {
        if sw == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 560),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            w.title = "NotchSchedule 設定"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(s: store, m: m))
            w.center()
            sw = w
        }
        store.load()
        hide()
        NSApp.activate(ignoringOtherApps: true)
        sw?.makeKeyAndOrderFront(nil)
    }

    // MARK: 選單 (選單列圖示 & 面板齒輪共用)
    func item(_ t: String, _ a: Selector, _ k: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: t, action: a, keyEquivalent: k); i.target = self; return i
    }
    func check(_ t: String, _ key: String) -> NSMenuItem {
        let i = item(t, #selector(flip(_:))); i.representedObject = key
        i.state = ud.bool(forKey: key) ? .on : .off; return i
    }

    func buildMenu() {
        if si == nil {
            si = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            si.button?.image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "NotchSchedule")
        }
        let mn = NSMenu()
        mn.addItem(item("顯示課表", #selector(showMenu)))
        mn.addItem(item("設定…", #selector(openSettings), ","))
        mn.addItem(item("新手教學", #selector(tourMenu)))
        mn.addItem(item(u.newVer.map { "⬆️ 更新到 v\($0)" } ?? "檢查更新…", #selector(updateMenu)))
        mn.addItem(.separator())
        mn.addItem(check("時間軸模式", "axis"))
        mn.addItem(check("瀏海倒數", "wing"))
        mn.addItem(check("顯示行事曆", "cal"))
        mn.addItem(.separator())
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let vi = NSMenuItem(title: "NotchSchedule v\(v)", action: nil, keyEquivalent: ""); vi.isEnabled = false
        mn.addItem(vi)
        mn.addItem(item("結束 NotchSchedule", #selector(quit), "q"))
        menu = mn; si.menu = mn
    }

    func popMenu() { menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
    @objc func showMenu() { show(hold: 10) }
    @objc func flip(_ s: NSMenuItem) {
        guard let k = s.representedObject as? String else { return }
        let v = !ud.bool(forKey: k)
        if k == "cal" && v {
            m.requestCal { ok in
                if ok { self.ud.set(true, forKey: "cal") }
                else { self.openSettings() }                    // 沒權限 -> 打開設定的行事曆分頁說明
            }
            return
        }
        ud.set(v, forKey: k)
    }
    @objc func tourMenu() { startTour() }
    @objc func quit() { NSApp.terminate(nil) }
}

extension Notification.Name {
    static let nsTour = Notification.Name("NotchScheduleReplayTour")
    static let nsDemo = Notification.Name("NotchScheduleDemoWings")
    static let nsDemoRemind = Notification.Name("NotchScheduleDemoRemind")
    static let nsUpdate = Notification.Name("NotchScheduleUpdate")
    static let nsCheckUpdate = Notification.Name("NotchScheduleCheckUpdate")
}

@main enum Main {
    static let ad = AD()
    static func main() { let a = NSApplication.shared; a.delegate = ad; a.run() }
}
