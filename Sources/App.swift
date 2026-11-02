// 瀏海偵測、選單、上課前提醒
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
    let m = M(), u = UI(), ud = UserDefaults.standard
    var p: Panel!, si: NSStatusItem!, t: Timer?, t2: Timer?
    var entered = false, holdUntil: Date?, hoverAt: Date?, outAt: Date?
    var menu = NSMenu()
    var sent = Set<String>()                                     // 已提醒過的課
    let W: CGFloat = 720, H: CGFloat = 500, pad: CGFloat = 30    // pad: 陰影留白

    var scr: NSScreen { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main! }
    var nw: CGFloat {
        let s = scr
        if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea { return s.frame.width - l.width - r.width }
        return 200
    }
    var nh: CGFloat { max(scr.safeAreaInsets.top, 24) }
    // 觸發區: 瀏海 (有倒數時含兩翼)
    var zone: NSRect {
        let f = scr.frame, w = nw + (m.wing && m.soon != nil ? 2 * Root.wingW : 0)
        return NSRect(x: f.midX - w / 2, y: f.maxY - nh, width: w, height: nh + 2)
    }
    var full: NSRect { let f = scr.frame; return NSRect(x: f.midX - W / 2, y: f.maxY - H, width: W, height: H) }

    func place() {
        let f = scr.frame
        u.nw = nw; u.nh = nh
        p.setFrame(NSRect(x: f.midX - W / 2 - pad, y: f.maxY - H - pad, width: W + 2 * pad, height: H + pad), display: true)
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        ud.register(defaults: ["lead": 10, "pop": true, "noti": true, "cal": false, "axis": false, "wing": true])
        NSApp.setActivationPolicy(.accessory)
        m.refresh()
        p = Panel(NSHostingView(rootView: Root(m: m, u: u, W: W, H: H, onMenu: { [weak self] in self?.popMenu() })))
        p.ignoresMouseEvents = true
        place()
        p.orderFrontRegardless()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.place() }
        buildMenu()
        let nc = UNUserNotificationCenter.current(); nc.delegate = self
        if ud.bool(forKey: "noti") { nc.requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        t = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        t2 = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.m.refresh(); self?.remind() }
        remind()
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) { h([.banner, .sound]) }

    // MARK: 滑鼠 (停 0.12 秒才打開，離開 0.25 秒才收起，避免誤觸)
    func tick() {
        let ms = NSEvent.mouseLocation
        if !u.open {
            if zone.contains(ms) {
                if hoverAt == nil { hoverAt = Date() }
                else if Date().timeIntervalSince(hoverAt!) > 0.12 { show() }
            } else { hoverAt = nil }
            return
        }
        if full.insetBy(dx: -12, dy: -12).contains(ms) { entered = true; outAt = nil; return }
        if let h = holdUntil, !entered, Date() < h { return }
        if outAt == nil { outAt = Date() }
        else if Date().timeIntervalSince(outAt!) > 0.25 { hide() }
    }

    // hold: 自動/選單打開時，滑鼠沒進來也停留幾秒
    func show(hold: TimeInterval? = nil) {
        holdUntil = hold.map { Date().addingTimeInterval($0) }
        entered = false; outAt = nil; hoverAt = nil
        if u.open { return }
        m.refresh()
        p.ignoresMouseEvents = false
        u.open = true
    }

    func hide() {
        u.open = false
        p.ignoresMouseEvents = true
        hoverAt = nil; outAt = nil
    }

    // MARK: 上課前提醒
    func remind() {
        let lead = ud.integer(forKey: "lead"); guard lead > 0 else { return }
        for o in m.occs where !sent.contains(o.id) {
            let x = o.st.timeIntervalSinceNow
            guard x > 0 && x <= Double(lead * 60) else { continue }
            sent.insert(o.id)
            if ud.bool(forKey: "pop") { show(hold: 10) }
            if ud.bool(forKey: "noti") {
                let c = UNMutableNotificationContent()
                c.title = "\(dur(Int(ceil(x / 60))))後：\(o.c) \(o.k)"
                c.body = "\(tma(o.st)) – \(tma(o.en))\(o.r.isEmpty ? "" : " · " + o.r)"
                c.sound = .default
                UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: o.id, content: c, trigger: nil))
            }
        }
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
        mn.addItem(item("編輯課表…", #selector(edit)))
        mn.addItem(.separator())
        mn.addItem(check("時間軸模式", "axis"))
        mn.addItem(check("瀏海倒數（上課前 15 分鐘起）", "wing"))
        mn.addItem(.separator())
        let sub = NSMenu(), lead = ud.integer(forKey: "lead")
        for x in [0, 5, 10, 15, 30] {
            let i = item(x == 0 ? "關閉" : "\(x) 分鐘前", #selector(setLead(_:)))
            i.tag = x; i.state = x == lead ? .on : .off; sub.addItem(i)
        }
        let li = NSMenuItem(title: "上課前提醒", action: nil, keyEquivalent: ""); li.submenu = sub; mn.addItem(li)
        mn.addItem(check("提醒時自動彈出課表", "pop"))
        mn.addItem(check("提醒時發送系統通知", "noti"))
        mn.addItem(check("顯示行事曆事件（含 Google 行事曆）", "cal"))
        let lg = item("開機自動啟動", #selector(login)); lg.state = SMAppService.mainApp.status == .enabled ? .on : .off
        mn.addItem(lg)
        mn.addItem(.separator())
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let vi = NSMenuItem(title: "NotchSchedule v\(v)", action: nil, keyEquivalent: ""); vi.isEnabled = false
        mn.addItem(vi)
        mn.addItem(item("結束 NotchSchedule", #selector(quit), "q"))
        menu = mn; si.menu = mn
    }

    func popMenu() { menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil) }
    @objc func showMenu() { show(hold: 10) }
    @objc func edit() {
        _ = loadSched()                                          // 確保檔案存在
        NSWorkspace.shared.open([sfile], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
    }
    @objc func setLead(_ s: NSMenuItem) { ud.set(s.tag, forKey: "lead"); buildMenu() }
    @objc func flip(_ s: NSMenuItem) {
        guard let k = s.representedObject as? String else { return }
        let v = !ud.bool(forKey: k); ud.set(v, forKey: k)
        if k == "noti" && v { UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        if k == "cal" && v {
            m.requestCal { ok in
                if !ok {
                    self.ud.set(false, forKey: "cal")
                    self.alert("沒有行事曆權限", "請到「系統設定 → 隱私權與安全性 → 行事曆」允許 NotchSchedule，再重新勾選。")
                }
                self.m.refresh(); self.buildMenu()
            }
        }
        m.refresh(); buildMenu()
    }
    @objc func login() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { alert("無法設定開機啟動", "請先把 App 放在「應用程式」資料夾再試。\n\(error.localizedDescription)") }
        buildMenu()
    }
    @objc func quit() { NSApp.terminate(nil) }

    func alert(_ a: String, _ b: String) {
        let x = NSAlert(); x.messageText = a; x.informativeText = b
        NSApp.activate(ignoringOtherApps: true); x.runModal()
    }
}

@main enum Main {
    static let ad = AD()
    static func main() { let a = NSApplication.shared; a.delegate = ad; a.run() }
}
