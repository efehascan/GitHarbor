import Foundation
import Observation

/// Seçili deponun değişiklikler ekranı: seçili dosya, farkı, satır seçimi, commit mesajı, stash listesi.
/// Her işlemden sonra `onChange` çağrılır (durum yenilensin); FSEvents de ayrıca yeniler.
@MainActor
@Observable
public final class ChangesSession {
    public let repo: RepoEntry
    public private(set) var status: RepoStatus = RepoStatus()

    public private(set) var selected: FileChange?
    public private(set) var diff: FileDiff?
    public private(set) var diffLoading = false
    public var lineSelection = Set<DiffLineRef>()

    public var summary = ""
    public var details = ""
    public var amend = false {
        didSet { if amend != oldValue { Task { await amendChanged() } } }
    }

    public private(set) var stashes: [StashEntry] = []
    public private(set) var operation: RepoOperation = .none
    public var conflicts: [FileChange] { status.changes.filter { $0.kind == .conflicted } }
    public private(set) var busy = false
    public var lastError: String?

    @ObservationIgnored private let onChange: () -> Void
    @ObservationIgnored private var diffToken = 0

    public init(repo: RepoEntry, onChange: @escaping () -> Void) {
        self.repo = repo
        self.onChange = onChange
    }

    public var staged: [FileChange] { status.changes.filter(\.staged) }
    public var unstaged: [FileChange] { status.changes.filter { !$0.staged } }
    public var canCommit: Bool {
        !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (!staged.isEmpty || amend) && !busy
            && !status.changes.contains { $0.kind == .conflicted }
    }

    // MARK: - Durum

    /// Depo durumu değişti: seçili dosya artık yoksa aynı yoldaki diğer kayda ya da ilk dosyaya geç.
    public func update(status new: RepoStatus, operation op: RepoOperation) {
        operation = op
        update(status: new)
    }

    public func update(status new: RepoStatus) {
        let changed = new != status
        status = new
        if let current = selected {
            if !new.changes.contains(current) {
                select(new.changes.first { $0.path == current.path } ?? new.changes.first)
            } else if changed {
                reloadDiff(keepSelection: true)
            }
        } else if let first = new.changes.first {
            select(first)
        }
    }

    public func select(_ change: FileChange?) {
        guard change != selected || diff == nil else { return }
        selected = change
        lineSelection = []
        reloadDiff(keepSelection: false)
    }

    private func reloadDiff(keepSelection: Bool) {
        diffToken += 1
        let token = diffToken
        guard let change = selected else { diff = nil; return }
        diffLoading = true
        Task {
            let result = try? await Git.diff(path: change.path, staged: change.staged,
                                             untracked: change.kind == .untracked, in: repo.path)
            guard token == diffToken else { return }
            if !keepSelection || result != diff { lineSelection = [] }
            diff = result
            diffLoading = false
        }
    }

    public func loadStashes() async {
        stashes = (try? await Git.stashes(in: repo.path)) ?? []
    }

    // MARK: - Satır seçimi

    public func toggleLine(_ ref: DiffLineRef, extend: Bool) {
        guard let diff, isChange(ref, in: diff) else { return }
        if extend, let anchor = lineSelection.max() {
            let lo = min(anchor, ref), hi = max(anchor, ref)
            for r in PatchBuilder.changeRefs(in: diff) where r >= lo && r <= hi { lineSelection.insert(r) }
        } else if lineSelection.contains(ref) {
            lineSelection.remove(ref)
        } else {
            lineSelection.insert(ref)
        }
    }

    public func selectHunk(_ index: Int) {
        guard let diff else { return }
        let refs = PatchBuilder.changeRefs(in: diff, hunk: index)
        if refs.isSubset(of: lineSelection) { lineSelection.subtract(refs) } else { lineSelection.formUnion(refs) }
    }

    private func isChange(_ ref: DiffLineRef, in diff: FileDiff) -> Bool {
        guard diff.hunks.indices.contains(ref.hunk), diff.hunks[ref.hunk].lines.indices.contains(ref.line) else { return false }
        let k = diff.hunks[ref.hunk].lines[ref.line].kind
        return k == .added || k == .removed
    }

    // MARK: - İşlemler

    public func stage(_ changes: [FileChange]) async {
        await perform { try await Git.stage(Array(Set(changes.map(\.path))), in: self.repo.path) }
    }

    public func unstage(_ changes: [FileChange]) async {
        await perform { try await Git.unstage(Array(Set(changes.map(\.path))), in: self.repo.path) }
    }

    public func stageAll() async { await stage(unstaged) }
    public func unstageAll() async { await unstage(staged) }

    /// Çalışma klasöründeki değişiklikleri geri alır (izlenmeyenler Çöp Sepeti'ne).
    public func discard(_ changes: [FileChange]) async {
        let work = changes.filter { !$0.staged }
        let untracked = work.filter { $0.kind == .untracked }.map(\.path)
        let tracked = work.filter { $0.kind != .untracked }.map(\.path)
        await perform { try await Git.discard(tracked: tracked, untracked: untracked, in: self.repo.path) }
    }

    /// Seçili satırları: çalışma farkında sahneye ekler, sahne farkında çıkarır.
    public func applySelectionToIndex() async {
        guard let diff, let change = selected, !lineSelection.isEmpty else { return }
        if change.kind == .untracked {
            await stage([change]); return
        }
        let direction: PatchBuilder.Direction = change.staged ? .reverse : .forward
        guard let patch = PatchBuilder.patch(for: diff, selecting: lineSelection, direction: direction) else { return }
        await perform { try await Git.apply(patch: patch, cached: true, reverse: change.staged, in: self.repo.path) }
    }

    /// Çalışma farkındaki seçili satırları geri alır.
    public func discardSelection() async {
        guard let diff, let change = selected, !change.staged, change.kind != .untracked, !lineSelection.isEmpty,
              let patch = PatchBuilder.patch(for: diff, selecting: lineSelection, direction: .reverse) else { return }
        await perform { try await Git.apply(patch: patch, cached: false, reverse: true, in: self.repo.path) }
    }

    public func commit() async {
        guard canCommit else { return }
        let body = details.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = summary.trimmingCharacters(in: .whitespacesAndNewlines) + (body.isEmpty ? "" : "\n\n" + body)
        let amending = amend
        let ok = await perform { try await Git.commit(message: message, amend: amending, in: self.repo.path) }
        if ok {
            summary = ""
            details = ""
            amend = false
        }
    }

    public func stash(message: String?) async {
        await perform { try await Git.stashPush(message: message, includeUntracked: true, in: self.repo.path) }
        await loadStashes()
    }

    public func restore(_ entry: StashEntry, pop: Bool) async {
        await perform { try await Git.stashApply(entry.ref, pop: pop, in: self.repo.path) }
        await loadStashes()
    }

    public func drop(_ entry: StashEntry) async {
        await perform { try await Git.stashDrop(entry.ref, in: self.repo.path) }
        await loadStashes()
    }

    // MARK: - Çakışma

    public func resolve(_ change: FileChange, take side: Git.ConflictSide) async {
        await perform { try await Git.resolve(change.path, take: side, in: self.repo.path) }
    }

    public func markResolved(_ change: FileChange) async {
        await perform { try await Git.markResolved(change.path, in: self.repo.path) }
    }

    public func abortOperation() async {
        let op = operation
        await perform { try await Git.abort(op, in: self.repo.path) }
        operation = await Git.operation(in: repo.path)
    }

    public func continueOperation() async {
        let op = operation
        await perform { try await Git.continueOperation(op, in: self.repo.path) }
        operation = await Git.operation(in: repo.path)
    }

    private func amendChanged() async {
        if amend, summary.isEmpty, details.isEmpty, let last = await Git.lastCommitMessage(in: repo.path) {
            let parts = last.components(separatedBy: "\n\n")
            summary = parts.first ?? ""
            details = parts.dropFirst().joined(separator: "\n\n")
        }
    }

    @discardableResult
    private func perform(_ work: @escaping () async throws -> Void) async -> Bool {
        busy = true
        defer { busy = false; onChange() }
        do {
            try await work()
            lastError = nil
            return true
        } catch {
            lastError = "\(error)"
            return false
        }
    }
}
