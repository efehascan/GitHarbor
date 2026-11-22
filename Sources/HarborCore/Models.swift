import Foundation

/// Kenar çubuğundaki bir depo kaydı. `path` çalışma klasörünün mutlak yolu.
public struct RepoEntry: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var path: String
    public var name: String
    public init(id: UUID = UUID(), path: String, name: String) {
        self.id = id
        self.path = path
        self.name = name
    }
}

/// Kullanıcının adlandırdığı klasör; depoları sırayla tutar.
public struct RepoFolder: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var repoIDs: [UUID]
    public init(id: UUID = UUID(), name: String, repoIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.repoIDs = repoIDs
    }
}

/// Kalıcı çalışma alanı: bütün depolar, klasörler ve klasörsüz depoların sırası.
/// Kural: her depo ya tam bir klasörde ya da `ungrouped` içindedir (ikisi birden ya da hiçbiri değil).
public struct Workspace: Codable, Hashable, Sendable {
    public var repos: [RepoEntry]
    public var folders: [RepoFolder]
    public var ungrouped: [UUID]
    public init(repos: [RepoEntry] = [], folders: [RepoFolder] = [], ungrouped: [UUID] = []) {
        self.repos = repos
        self.folders = folders
        self.ungrouped = ungrouped
    }
}

/// Bir dosyadaki değişikliğin türü.
public enum ChangeKind: String, Codable, Hashable, Sendable {
    case added, modified, deleted, renamed, copied, typeChanged, untracked, conflicted
}

/// Çalışma klasöründeki bir değişiklik. Aynı dosya hem sahnede hem dışında değişmişse iki kayıt olur
/// (`staged: true` ve `staged: false`).
public struct FileChange: Hashable, Identifiable, Sendable {
    public var path: String
    public var oldPath: String?
    public var kind: ChangeKind
    public var staged: Bool
    public var id: String { (staged ? "S:" : "W:") + path }
    public init(path: String, oldPath: String? = nil, kind: ChangeKind, staged: Bool) {
        self.path = path
        self.oldPath = oldPath
        self.kind = kind
        self.staged = staged
    }
}

/// `git status --porcelain=v2 --branch -z` çıktısının özeti.
public struct RepoStatus: Hashable, Sendable {
    /// Dal adı; ayrık HEAD'de nil.
    public var branch: String?
    public var commit: String?
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    public var changes: [FileChange]
    public init(branch: String? = nil, commit: String? = nil, upstream: String? = nil,
                ahead: Int = 0, behind: Int = 0, changes: [FileChange] = []) {
        self.branch = branch
        self.commit = commit
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.changes = changes
    }
    public var isClean: Bool { changes.isEmpty }
}
