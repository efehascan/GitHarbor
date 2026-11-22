import Foundation
import Observation

/// Geçmiş ekranı ve dal seçici: sayfalı commit listesi, seçili commit'in farkları, dallar, etiketler.
@MainActor
@Observable
public final class HistorySession {
    public let repo: RepoEntry
    public private(set) var commits: [CommitInfo] = []
    public private(set) var reachedEnd = false
    public private(set) var loading = false

    public private(set) var selected: CommitInfo?
    public private(set) var message = ""
    public private(set) var files: [FileDiff] = []
    public var selectedFile = 0

    public private(set) var branches: [BranchInfo] = []
    public private(set) var tags: [TagInfo] = []
    /// Mesajlardaki #123 bağlantıları için.
    public private(set) var gitHubRepo: GitHubRepoID?
    public private(set) var busy = false
    public var lastError: String?

    @ObservationIgnored private let onChange: () -> Void
    @ObservationIgnored private var headSHA: String?
    @ObservationIgnored private var detailToken = 0
    static let pageSize = 200

    public init(repo: RepoEntry, onChange: @escaping () -> Void) {
        self.repo = repo
        self.onChange = onChange
    }

    public var localBranches: [BranchInfo] { branches.filter { !$0.isRemote } }
    /// Yerelde karşılığı olmayan uzak dallar.
    public var remoteOnlyBranches: [BranchInfo] {
        let tracked = Set(localBranches.compactMap(\.upstream))
        return branches.filter { $0.isRemote && !tracked.contains($0.name) }
    }

    /// Bir commit'i gösteren etiketler.
    public func tags(for sha: String) -> [String] { tags.filter { $0.commit == sha }.map(\.name) }

    // MARK: - Yükleme

    /// HEAD değiştiyse listeyi baştan yükler (commit, dal değişimi, pull sonrası).
    public func reload(force: Bool = false) async {
        let head = try? await Git.run(["rev-parse", "-q", "--verify", "HEAD"], in: repo.path)
        let sha = head.map { String(decoding: $0, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) }
        async let b = try? Git.branches(in: repo.path)
        async let t = try? Git.tags(in: repo.path)
        branches = await b ?? []
        tags = await t ?? []
        if gitHubRepo == nil { gitHubRepo = await Git.gitHubRepo(in: repo.path) }
        guard force || sha != headSHA || commits.isEmpty else { return }
        headSHA = sha
        loading = true
        let first = (try? await Git.log(limit: Self.pageSize, in: repo.path)) ?? []
        commits = first
        reachedEnd = first.count < Self.pageSize
        loading = false
        if let selected, let same = first.first(where: { $0.sha == selected.sha }) {
            self.selected = same
        } else {
            await select(first.first)
        }
    }

    public func loadMore() async {
        guard !reachedEnd, !loading else { return }
        loading = true
        let next = (try? await Git.log(limit: Self.pageSize, skip: commits.count, in: repo.path)) ?? []
        commits += next
        reachedEnd = next.count < Self.pageSize
        loading = false
    }

    public func select(_ commit: CommitInfo?) async {
        guard commit?.sha != selected?.sha || files.isEmpty else { return }
        selected = commit
        selectedFile = 0
        detailToken += 1
        let token = detailToken
        guard let commit else { files = []; message = ""; return }
        async let m = try? Git.commitMessage(commit.sha, in: repo.path)
        async let d = try? Git.commitDiff(commit.sha, in: repo.path)
        let (msg, diffs) = await (m, d)
        guard token == detailToken else { return }
        message = msg ?? commit.subject
        files = diffs ?? []
    }

    // MARK: - İşlemler

    public func switchTo(_ branch: BranchInfo) async { await perform { try await Git.switchBranch(branch, in: self.repo.path) } }

    public func createBranch(_ name: String, from start: String?) async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        await perform { try await Git.createBranch(n, from: start, checkout: true, in: self.repo.path) }
    }

    public func rename(_ branch: BranchInfo, to name: String) async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != branch.name else { return }
        await perform { try await Git.renameBranch(branch.name, to: n, in: self.repo.path) }
    }

    public func delete(_ branch: BranchInfo, force: Bool) async {
        await perform { try await Git.deleteBranch(branch.name, force: force, in: self.repo.path) }
    }

    public func merge(_ branch: BranchInfo) async { await perform { try await Git.merge(branch.name, in: self.repo.path) } }
    public func rebase(onto branch: BranchInfo) async { await perform { try await Git.rebase(onto: branch.name, in: self.repo.path) } }
    public func cherryPick(_ commit: CommitInfo) async { await perform { try await Git.cherryPick(commit.sha, in: self.repo.path) } }
    public func revert(_ commit: CommitInfo) async { await perform { try await Git.revert(commit, in: self.repo.path) } }
    public func checkout(_ commit: CommitInfo) async { await perform { try await Git.checkout(commit: commit.sha, in: self.repo.path) } }

    public func createTag(_ name: String, at commit: CommitInfo, message: String?) async {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        await perform { try await Git.createTag(n, at: commit.sha, message: message, in: self.repo.path) }
    }

    public func deleteTag(_ name: String) async { await perform { try await Git.deleteTag(name, in: self.repo.path) } }
    public func pushTag(_ name: String) async { await perform { try await Git.pushTag(name, in: self.repo.path) } }

    private func perform(_ work: @escaping () async throws -> Void) async {
        busy = true
        do {
            try await work()
            lastError = nil
        } catch {
            lastError = "\(error)"
        }
        busy = false
        onChange()
        await reload(force: true)
    }
}
