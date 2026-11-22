import CoreServices
import Foundation

/// Depo klasörlerini FSEvents ile izler; değişen depoyu (kök yolunu) bildirir.
/// Yoklama yok: değişiklik olmadıkça hiç iş yapılmaz. Olaylar `latency` saniye biriktirilir.
public final class RepoWatcher: @unchecked Sendable {
    public typealias Handler = @Sendable (Set<String>) -> Void

    private var stream: FSEventStreamRef?
    private var roots: [String] = []
    private let handler: Handler
    private let latency: CFTimeInterval
    private let queue = DispatchQueue(label: "harbor.watcher", qos: .utility)

    public init(latency: CFTimeInterval = 0.4, handler: @escaping Handler) {
        self.latency = latency
        self.handler = handler
    }

    deinit { stop() }

    /// İzlenen kökleri değiştirir (aynıysa akışı yeniden kurmaz).
    public func watch(_ paths: [String]) {
        let normalized = paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path }.sorted()
        guard normalized != roots else { return }
        stop()
        roots = normalized
        guard !normalized.isEmpty else { return }

        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, count, pathsPointer, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<RepoWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = Unmanaged<CFArray>.fromOpaque(pathsPointer).takeUnretainedValue() as? [String] ?? []
            watcher.dispatch(Array(array.prefix(count)))
        }
        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        guard let s = FSEventStreamCreate(nil, callback, &context, normalized as CFArray,
                                          FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags) else { return }
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
        stream = s
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    private func dispatch(_ paths: [String]) {
        let changed = RepoWatcher.affectedRoots(paths, roots: roots)
        if !changed.isEmpty { handler(changed) }
    }

    /// Olay yollarını depo köklerine eşler. `.git` içindeki gürültü (nesneler, kilit dosyaları, loglar)
    /// sayılmaz; HEAD, index, refs ve FETCH_HEAD değişimi sayılır (commit, dal değişimi, fetch).
    public static func affectedRoots(_ paths: [String], roots: [String]) -> Set<String> {
        var result = Set<String>()
        for path in paths {
            guard let root = roots.first(where: { path == $0 || path.hasPrefix($0 + "/") }) else { continue }
            let rel = path == root ? "" : String(path.dropFirst(root.count + 1))
            if rel == ".git" || rel.hasPrefix(".git/") {
                let inner = rel == ".git" ? "" : String(rel.dropFirst(5))
                let relevant = inner == "HEAD" || inner == "index" || inner == "FETCH_HEAD"
                    || inner == "MERGE_HEAD" || inner.hasPrefix("refs/")
                if !relevant || inner.hasSuffix(".lock") { continue }
            }
            result.insert(root)
        }
        return result
    }
}
