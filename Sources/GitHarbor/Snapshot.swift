import AppKit
import HarborCore

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

    @MainActor
    static func runIfRequested(store: HarborStore) {
        guard let output = outputPath else { return }
        if let name = value(after: "--select") {
            store.selection = store.workspace.repos.first { $0.name == name }?.id
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard let window = NSApp.windows.first(where: { $0.isVisible }) ,
                  let view = window.contentView?.superview ?? window.contentView,
                  let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { exit(1) }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            exit(0)
        }
    }
}
