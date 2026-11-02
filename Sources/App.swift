// 瀏海偵測、選單列圖示、上課前提醒
import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement

final class Panel: NSPanel {
    init(_ v: NSView) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear; isOpaque = false; hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = v
    }
    override var canBecomeKey: Bool { true }
}

final class AD: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    let m = M(), ud = UserDefaults.standard
    var p: Panel!, si: NSStatusItem!, t: Timer?, t2: Timer?
    var open = false, entered = false, holdUntil: Date?
    var menu = NSMenu()
    var sent = Set<String>()                                     // 已提醒過的課
    let W: CGFloat = 720, H: CGFloat = 470

    var scr: NSScreen { NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main! }
    var notch: NSRect {
        let s = scr, f = s.frame
        var w: CGFloat = 200
        if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea { w = f.width - l.width - r.width }
        let h = max(s.safeAreaInsets.top, 24)
        return NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h + 2)
    }
    var full: NSRect { let f = scr.frame; return NSRect(x: f.midX - W / 2, y: f.maxY - H, width: W, height: H) }

    func applicationDidFinishLaunching(_ n: Notification) {
        ud.register(defaults: ["lead": 10, "pop": true, "noti": true, "cal": false])
        NSApp.setActivationPolicy(.accessory)
        m.refresh()
        p = Panel(NSHostingView(rootView: SchedView(m: m, top: max(scr.safeAreaInsets.top, 24), onMenu: { [weak self] in self?.popMenu() })))
        buildMenu()
        let nc = UNUserNotificationCenter.current(); nc.delegate = self
        if ud.bool(forKey: "noti") { nc.requestAuthorization(options: [.alert, .sound]) { _, _ in } }
        t = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        t2 = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.m.refresh(); self?.remind() }
        remind()
    }

    func userNotificationCenter(_ c: UNUserNotificationCenter, willPresent n: UNNotification,
                                withCompletionHandler h: @escaping (UNNotificationPresentationOptions) -> Void) { h([.banner, .sound]) }

    // MARK: 滑鼠
    func tick() {
        let ms = NSEvent.mouseLocation
        if !open { if notch.contains(ms) { show() }; return }
        if full.insetBy(dx: -12, dy: -12).contains(ms) { entered = true; return }
        if holdUntil == nil || entered || Date() > holdUntil! { hide() }
    }

    // hold: 自動/選單打開時，滑鼠沒進來也先停留幾秒
    func show(hold: TimeInterval? = nil) {
        holdUntil = hold.map { Date().addingTimeInterval($0) }; entered = false
        if open { return }
        open = true
        m.refresh()
        p.setFrame(full.offsetBy(dx: 0, dy: 12), display: false)
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { c in
            c.duration = 0.18
            p.animator().setFrame(full, display: true)
            p.animator().alphaValue = 1
        }
    }

    func hide() {
        open = false
        NSAnimationContext.runAnimationGroup({ c in
            c.duration = 0.15
            p.animator().alphaValue = 0
        }, completionHandler: { [weak self] in if self?.open == false { self?.p.orderOut(nil) } })
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

    // MARK: 選單列
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
