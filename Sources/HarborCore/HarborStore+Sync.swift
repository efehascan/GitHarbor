import Foundation

/// Senkron durumu (depo başına). Gözlenen depolar `HarborStore.sync` sözlüğünde.
public struct RepoSyncState: Hashable, Sendable {
    public var lastFetch: Date?
    public var running: SyncActivity?
    /// Otomatik çekilemeyen ama bekleyen değişikliğin sebebi.
    public var attention: String?
    /// Son otomatik ya da elle işlem hatası.
    public var error: String?
    public var operation: RepoOperation = .none
    public init() {}
}

public enum SyncActivity: String, Hashable, Sendable {
    case fetching, pulling, pushing
}

extension HarborStore {
    static let settingsKey = "syncSettings"

    public static func loadSettings() -> SyncSettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey),
              let s = try? JSONDecoder().decode(SyncSettings.self, from: data) else { return SyncSettings() }
        return s
    }

    public func updateSettings(_ change: (inout SyncSettings) -> Void) {
        change(&settings)
        if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: Self.settingsKey) }
        startAutoSync()
    }

    /// Otomatik senkron: 30 sn'de bir yalnızca *karar* verilir (ucuz); fetch, depo başına ayar aralığında yapılır.
    /// Aynı anda en fazla 4 fetch.
    func startAutoSync() {
        autoTimer?.invalidate()
        autoTimer = nil
        guard settings.autoFetch else { return }
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.autoTick() }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        autoTimer = timer
        autoTick()
    }

    func autoTick() {
        let now = Date()
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let due = workspace.repos.filter { repo in
            sync[repo.id]?.running == nil && statuses[repo.id]?.upstream != nil
                && AutoSyncPolicy.shouldFetch(lastFetch: sync[repo.id]?.lastFetch, now: now, settings: settings, lowPower: lowPower)
        }
        let slots = max(0, 4 - workspace.repos.filter { sync[$0.id]?.running != nil }.count)
        for repo in due.prefix(slots) {
            Task { await fetch(repo.id, automatic: true) }
        }
    }

    // MARK: - İşlemler

    /// Fetch; otomatikse ardından güvenliyse ileri sarar ya da dikkat notu bırakır.
    public func fetch(_ id: UUID, automatic: Bool = false) async {
        guard let repo = workspace.repo(id) else { return }
        await run(id, .fetching, quietErrors: automatic) {
            try await Git.fetch(in: repo.path)
        }
        sync[id, default: RepoSyncState()].lastFetch = Date()
        guard let status = try? await Git.status(in: repo.path) else { refresh(id); return }
        let operation = await Git.operation(in: repo.path)
        sync[id, default: RepoSyncState()].operation = operation
        statuses[id] = status
        switch AutoSyncPolicy.decide(status: status, operation: operation, settings: settings) {
        case .fastForward:
            if automatic || settings.autoPull {
                await run(id, .pulling, quietErrors: automatic) { try await Git.fastForward(in: repo.path) }
            }
            sync[id, default: RepoSyncState()].attention = nil
        case .needsAttention(let reason):
            sync[id, default: RepoSyncState()].attention = reason
        case .nothing:
            sync[id, default: RepoSyncState()].attention = nil
        }
        refresh(id)
        if automatic { autoTick() }      // boşalan yere sıradaki depo
    }

    public func pull(_ id: UUID, mode: Git.PullMode) async {
        guard let repo = workspace.repo(id) else { return }
        await run(id, .pulling, quietErrors: false) { try await Git.pull(mode: mode, in: repo.path) }
        sync[id, default: RepoSyncState()].attention = nil
        await refreshOperation(id)
    }

    public func push(_ id: UUID) async {
        guard let repo = workspace.repo(id), let status = statuses[id], let branch = status.branch else { return }
        await run(id, .pushing, quietErrors: false) {
            try await Git.push(branch: branch, hasUpstream: status.upstream != nil, in: repo.path)
        }
        refresh(id)
    }

    public func refreshOperation(_ id: UUID) async {
        guard let repo = workspace.repo(id) else { return }
        sync[id, default: RepoSyncState()].operation = await Git.operation(in: repo.path)
        refresh(id)
    }

    public func clearSyncError(_ id: UUID) {
        sync[id]?.error = nil
    }

    private func run(_ id: UUID, _ activity: SyncActivity, quietErrors: Bool, _ work: @escaping () async throws -> Void) async {
        sync[id, default: RepoSyncState()].running = activity
        defer { sync[id]?.running = nil }
        do {
            try await work()
            sync[id]?.error = nil
        } catch {
            // Otomatik işlemde ağ yokluğu vb. sessizce kaydedilir; kullanıcıya rozet olarak gösterilir.
            sync[id]?.error = quietErrors ? "Otomatik senkron: \(error)" : "\(error)"
            if !quietErrors { syncAlert = "\(error)" }
        }
    }
}
