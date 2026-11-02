// 自動更新: 檢查 GitHub Releases 有沒有新版，下載、替換、重開
import Foundation
import AppKit

enum Updater {
    static let repo = "Ruix0525/NotchSchedule"
    static var current: String { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0" }

    struct Rel: Decodable {
        struct Asset: Decodable { let name: String; let browser_download_url: String }
        let tag_name: String
        let assets: [Asset]
    }

    // "0.10.0" > "0.9.3"
    static func newer(_ a: String, than b: String) -> Bool {
        let p = { (s: String) in s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 } }
        let x = p(a), y = p(b)
        for i in 0..<max(x.count, y.count) {
            let u = i < x.count ? x[i] : 0, v = i < y.count ? y[i] : 0
            if u != v { return u > v }
        }
        return false
    }

    // 有新版 -> (版本, 下載網址)
    static func check() async -> (String, URL)? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        guard let res = try? await URLSession.shared.data(for: req) else { return nil }
        let (d, r) = res
        guard (r as? HTTPURLResponse)?.statusCode == 200,
              let rel = try? JSONDecoder().decode(Rel.self, from: d),
              let a = rel.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let u = URL(string: a.browser_download_url),
              newer(rel.tag_name, than: current) else { return nil }
        return (rel.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")), u)
    }

    // 下載 -> 解壓縮 -> App 關掉後換成新版 -> 重新打開
    static func install(_ url: URL) async throws {
        let fm = FileManager.default
        let dest = Bundle.main.bundleURL
        guard fm.isWritableFile(atPath: dest.deletingLastPathComponent().path) else {
            throw FetchErr(errorDescription: "沒有權限寫入 \(dest.deletingLastPathComponent().path)")
        }
        let tmp = fm.temporaryDirectory.appendingPathComponent("ns-update-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let (f, _) = try await URLSession.shared.download(from: url)
        let zip = tmp.appendingPathComponent("update.zip")
        try fm.moveItem(at: f, to: zip)
        try run("/usr/bin/ditto", ["-x", "-k", zip.path, tmp.path])
        guard let app = try fm.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "app" }) else {
            throw FetchErr(errorDescription: "下載的檔案裡找不到 App")
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let sh = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        rm -rf "\(dest.path)"
        /usr/bin/ditto "\(app.path)" "\(dest.path)"
        /usr/bin/xattr -dr com.apple.quarantine "\(dest.path)" 2>/dev/null
        /usr/bin/open "\(dest.path)"
        rm -rf "\(tmp.path)"
        """
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", sh]
        try p.run()
        UserDefaults.standard.set(true, forKey: "justUpdated")
        await MainActor.run { NSApp.terminate(nil) }
    }

    static func run(_ exe: String, _ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: exe); p.arguments = args
        try p.run(); p.waitUntilExit()
        if p.terminationStatus != 0 { throw FetchErr(errorDescription: "解壓縮失敗") }
    }
}
