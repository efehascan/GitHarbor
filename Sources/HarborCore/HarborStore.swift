import Foundation
import Observation

/// Uygulamanın durumu: çalışma alanı (kalıcı), depo durumları, seçim.
/// Durum yalnızca açılışta ve dosya değişince (FSEvents) yenilenir; zamanlayıcıyla yoklama yok.
@MainActor
@Observable
public final class HarborStore {
    public private(set) var workspace: Workspace
    public private(set) var statuses: [UUID: RepoStatus] = [:]
    public private(set) var errors: [UUID: String] = [:]
    public var selection: UUID?

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var watcher: RepoWatcher?
    @ObservationIgnored private var inFlight = Set<UUID>()
    @ObservationIgnored private var pending = Set<UUID>()

    /// `fileURL` nil ise kaydetmez (önizleme, test).
    public init(fileURL: URL? = HarborStore.defaultFileURL) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let saved = try? JSONDecoder().decode(Workspace.self, from: data) {
            workspace = saved
        } else {
            workspace = Workspace()
        }
    }

    public nonisolated static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("GitHarbor/workspace.json")
    }

    // MARK: - Yaşam döngüsü

    public func start() {
        if watcher == nil {
            watcher = RepoWatcher { [weak self] roots in
                Task { @MainActor in self?.changed(roots: roots) }
            }
        }
        rewatch()
        refreshAll()
    }

    public func refreshAll() {
        for repo in workspace.repos { refresh(repo.id) }
    }

    /// Aynı depo için en fazla bir `git status` çalışır; arada gelen istekler tek bir tekrar olarak birleşir.
    public func refresh(_ id: UUID) {
        guard let repo = workspace.repo(id) else { return }
        if inFlight.contains(id) { pending.insert(id); return }
        inFlight.insert(id)
        Task {
            do {
                let status = try await Git.status(in: repo.path)
                statuses[id] = status
                errors[id] = nil
            } catch {
                errors[id] = FileManager.default.fileExists(atPath: repo.path) ? "\(error)" : "Klasör bulunamadı"
            }
            inFlight.remove(id)
            if pending.remove(id) != nil { refresh(id) }
        }
    }

    private func changed(roots: Set<String>) {
        for repo in workspace.repos where roots.contains(URL(fileURLWithPath: repo.path).standardizedFileURL.path) {
            refresh(repo.id)
        }
    }

    private func rewatch() {
        watcher?.watch(workspace.repos.map(\.path))
    }

    // MARK: - Düzenleme

    public func edit(_ change: (inout Workspace) -> Void) {
        var copy = workspace
        change(&copy)
        guard copy != workspace else { return }
        let added = Set(copy.repos.map(\.id)).subtracting(workspace.repos.map(\.id))
        workspace = copy
        for id in Set(statuses.keys).subtracting(copy.repos.map(\.id)) { statuses[id] = nil; errors[id] = nil }
        if let selection, copy.repo(selection) == nil { self.selection = nil }
        save()
        rewatch()
        for id in added { refresh(id) }
    }

    /// Seçilen klasörleri ekler: klasör bir depo kökü ise onu, değilse bir alt düzeydeki depo köklerini.
    /// Dönüş: eklenen depo sayısı.
    @discardableResult
    public func addRepositories(at urls: [URL], into folder: UUID? = nil) async -> Int {
        let found = await Task.detached(priority: .userInitiated) { HarborStore.discover(urls) }.value
        guard !found.isEmpty else { return 0 }
        var last: UUID?
        edit { w in
            for path in found {
                let entry = w.addRepo(path: path)
                if let folder { w.move(repo: entry.id, to: folder) }
                last = entry.id
            }
        }
        if let last { selection = last }
        return found.count
    }

    nonisolated static func discover(_ urls: [URL]) -> [String] {
        var result: [String] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            if Git.isRepositoryRoot(path) { result.append(path); continue }
            let children = (try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
            for child in children.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending })
            where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                && FileManager.default.fileExists(atPath: child.appendingPathComponent(".git").path) {
                result.append(child.standardizedFileURL.path)
            }
        }
        return result
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(workspace).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("GitHarbor: çalışma alanı kaydedilemedi: \(error)")
        }
    }
}
