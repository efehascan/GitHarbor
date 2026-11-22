import Foundation
import Observation

/// Uygulama genelinde GitHub hesabı. Token Anahtar Zinciri'nde; bellekte yalnızca API istemcisi içinde.
@MainActor
@Observable
public final class GitHubAccount {
    public private(set) var user: GitHubUser?
    public private(set) var connecting = false
    public var lastError: String?
    @ObservationIgnored public private(set) var api: GitHubAPI?

    public init() {
        if let token = TokenStore.load() {
            api = GitHubAPI(token: token)
            Task { await validate() }
        }
    }

    public var isConnected: Bool { api != nil }
    public var cliAvailable: Bool {
        ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].contains { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// GitHub CLI oturumundaki token'ı alıp doğrular.
    public func connectWithCLI() async {
        connecting = true
        defer { connecting = false }
        let token = await Task.detached { TokenStore.tokenFromGitHubCLI() }.value
        guard let token else {
            lastError = "GitHub CLI'da giriş bulunamadı. Terminalde `gh auth login` çalıştırıp tekrar dene."
            return
        }
        await connect(token: token)
    }

    public func connect(token raw: String) async {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        connecting = true
        defer { connecting = false }
        let candidate = GitHubAPI(token: token)
        do {
            user = try await candidate.currentUser()
            guard TokenStore.save(token) else {
                lastError = "Token Anahtar Zinciri'ne kaydedilemedi"
                return
            }
            api = candidate
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    public func signOut() {
        TokenStore.delete()
        api = nil
        user = nil
    }

    private func validate() async {
        guard let api else { return }
        do {
            user = try await api.currentUser()
        } catch let e as GitHubAPIError where e.status == 401 {
            signOut()
            lastError = "GitHub girişinin süresi dolmuş; yeniden bağlan."
        } catch {
            // Ağ yoksa token'ı silme; sonra yeniden denenir.
        }
    }
}

/// Bir deponun pull request ekranı.
@MainActor
@Observable
public final class PullRequestSession {
    public let repo: RepoEntry
    public private(set) var repoID: GitHubRepoID?
    public private(set) var resolved = false
    public private(set) var pulls: [PullRequest] = []
    public private(set) var summaries: [String: CheckSummary] = [:]
    public private(set) var selected: PullRequest?
    public private(set) var checks: [CheckRun] = []
    public private(set) var defaultBranch: String?
    public private(set) var loading = false
    public private(set) var busy = false
    public var lastError: String?

    @ObservationIgnored private let onChange: () -> Void

    public init(repo: RepoEntry, onChange: @escaping () -> Void) {
        self.repo = repo
        self.onChange = onChange
    }

    public func load(api: GitHubAPI) async {
        if !resolved {
            repoID = await Git.gitHubRepo(in: repo.path)
            resolved = true
        }
        guard let repoID else { return }
        loading = true
        defer { loading = false }
        do {
            async let prs = api.pullRequests(repoID)
            async let branch = try? api.defaultBranch(repoID)
            pulls = try await prs
            defaultBranch = await branch
            lastError = nil
        } catch {
            lastError = "\(error)"
            return
        }
        if let s = selected, let same = pulls.first(where: { $0.number == s.number }) {
            selected = same
        } else {
            selected = pulls.first
        }
        // CI özetleri paralel (en fazla 50 PR).
        await withTaskGroup(of: (String, CheckSummary).self) { group in
            for pr in pulls {
                group.addTask { (pr.head.sha, GitHubParsing.summarize((try? await api.checkRuns(repoID, sha: pr.head.sha)) ?? [])) }
            }
            for await (sha, summary) in group { summaries[sha] = summary }
        }
        await loadChecks(api: api)
    }

    public func select(_ pr: PullRequest?, api: GitHubAPI) async {
        selected = pr
        checks = []
        await loadChecks(api: api)
    }

    private func loadChecks(api: GitHubAPI) async {
        guard let repoID, let pr = selected else { checks = []; return }
        let runs = (try? await api.checkRuns(repoID, sha: pr.head.sha)) ?? []
        guard selected?.number == pr.number else { return }
        checks = runs.sorted { ($0.conclusion ?? "~", $0.name) < ($1.conclusion ?? "~", $1.name) }
    }

    public func checkout(_ pr: PullRequest) async {
        guard let repoID else { return }
        busy = true
        defer { busy = false; onChange() }
        do {
            try await Git.checkoutPullRequest(pr, repoID: repoID, in: repo.path)
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
    }

    /// Mevcut daldan PR açar. Dal uzakta yoksa önce yayınlanır.
    @discardableResult
    public func create(api: GitHubAPI, status: RepoStatus, title: String, body: String, base: String, draft: Bool) async -> PullRequest? {
        guard let repoID, let branch = status.branch else { return nil }
        busy = true
        defer { busy = false; onChange() }
        do {
            if status.upstream == nil || status.ahead > 0 {
                try await Git.push(branch: branch, hasUpstream: status.upstream != nil, in: repo.path)
            }
            let pr = try await api.createPullRequest(repoID, title: title, body: body, head: branch, base: base, draft: draft)
            lastError = nil
            await load(api: api)
            selected = pulls.first { $0.number == pr.number } ?? pr
            return pr
        } catch {
            lastError = "\(error)"
            return nil
        }
    }

    /// Mevcut dal için açık PR.
    public func pull(forBranch branch: String?) -> PullRequest? {
        guard let branch, let repoID else { return nil }
        return pulls.first { $0.head.ref == branch && $0.head.repoFullName?.lowercased() == repoID.slug.lowercased() }
    }
}
