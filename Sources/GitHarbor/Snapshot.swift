import AppKit
import HarborCore
import SwiftUI

/// `--snapshot çıktı.png [--workspace ws.json] [--select AD]`: pencereyi açar, durumlar gelince
/// pencerenin görüntüsünü PNG'ye yazar ve çıkar. Görsel kontrol içindir; kalıcı çalışma alanına dokunmaz.
enum Snapshot {
    static var outputPath: String? { value(after: "--snapshot") }
    static var workspaceURL: URL? {
        if let p = value(after: "--workspace") { return URL(fileURLWithPath: p) }
        // Görüntü modunda gerçek çalışma alanı kaydedilmesin: geçici kopyaya yönlendir.
        guard outputPath != nil else { return nil }
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-snapshot-ws.json")
        try? FileManager.default.removeItem(at: tmp)
        try? FileManager.default.copyItem(at: HarborStore.defaultFileURL, to: tmp)
        return tmp
    }

    private static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// `--api-smoke owner/repo`: GitHub CLI token'ıyla (kaydetmeden) kullanıcıyı, açık PR'ları ve CI özetini yazar.
    @MainActor
    static func runAPISmokeIfRequested() async {
        guard let slug = value(after: "--api-smoke") else { return }
        let parts = slug.split(separator: "/").map(String.init)
        guard parts.count == 2, let token = TokenStore.tokenFromGitHubCLI() else { print("token yok"); exit(2) }
        let api = GitHubAPI(token: token)
        let repo = GitHubRepoID(owner: parts[0], name: parts[1])
        do {
            print("kullanıcı:", try await api.currentUser().login)
            print("varsayılan dal:", try await api.defaultBranch(repo))
            let prs = try await api.pullRequests(repo)
            print("açık PR:", prs.count)
            for pr in prs.prefix(3) {
                let summary = GitHubParsing.summarize(try await api.checkRuns(repo, sha: pr.head.sha))
                print(" #\(pr.number) \(pr.head.ref) → \(pr.base.ref) taslak:\(pr.draft) CI:\(summary)")
            }
            exit(0)
        } catch {
            print("hata:", error)
            exit(1)
        }
    }

    /// Görsel test seçenekleri (scripts/visual-test.sh): `--appearance light|dark`, `--size 1320x820`, `--settings`.
    @MainActor
    static func applyTestOptions(store: HarborStore) {
        if let name = value(after: "--select") {
            store.selection = store.workspace.repos.first { $0.name == name }?.id
        }
        switch value(after: "--appearance") {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: break
        }
        if let size = value(after: "--size") {
            let p = size.split(separator: "x").compactMap { Double($0) }
            if p.count == 2, let w = NSApp.windows.first(where: { $0.title == "Git Harbor Desktop" }) {
                w.setFrame(NSRect(x: 80, y: 80, width: p[0], height: p[1]), display: true)
            }
        }
    }

    @MainActor
    static func runIfRequested(store: HarborStore) {
        guard let output = outputPath else { return }
        if let name = value(after: "--select") {
            store.selection = store.workspace.repos.first { $0.name == name }?.id
        }
        let args = CommandLine.arguments
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(args.contains("--slow") ? 6 : 3))
            let window: NSWindow?
            if args.contains("--settings") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                try? await Task.sleep(for: .seconds(1))
                window = NSApp.windows.first { $0.isVisible && $0.title != "Git Harbor Desktop" && $0.frame.width > 300 }
            } else if args.contains("--menubar") {
                let host = NSHostingView(rootView: MenuBarView(store: store).background(.background))
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                let w = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                w.contentView = host
                w.orderFront(nil)
                try? await Task.sleep(for: .seconds(0.5))
                window = w
            } else {
                window = NSApp.windows.filter { $0.isVisible }.max { $0.frame.width < $1.frame.width }
            }
            guard let window, let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            exit(0)
        }
    }
}
