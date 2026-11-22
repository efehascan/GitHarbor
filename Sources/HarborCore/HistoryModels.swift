import Foundation

/// Geçmişteki bir commit.
public struct CommitInfo: Hashable, Identifiable, Sendable {
    public var sha: String
    public var parents: [String]
    public var author: String
    public var email: String
    public var date: Date
    /// Bu commit'i gösteren referanslar: "HEAD -> main", "origin/main", "tag: v1.0" gibi (git'in %D biçimi, ", " ile bölünmüş).
    public var refs: [String]
    public var subject: String
    public var id: String { sha }
    public var shortSHA: String { String(sha.prefix(7)) }
    public var isMerge: Bool { parents.count > 1 }
    public init(sha: String, parents: [String], author: String, email: String, date: Date, refs: [String], subject: String) {
        self.sha = sha
        self.parents = parents
        self.author = author
        self.email = email
        self.date = date
        self.refs = refs
        self.subject = subject
    }
}

/// Yerel ya da uzak dal.
public struct BranchInfo: Hashable, Identifiable, Sendable {
    /// Kısa ad: "main", "feature/x" (yerel) ya da "origin/main" (uzak).
    public var name: String
    public var isRemote: Bool
    public var isHead: Bool
    public var commit: String
    /// Yerel dalın izlediği uzak dal ("origin/main"), yoksa nil.
    public var upstream: String?
    public var ahead: Int
    public var behind: Int
    /// Upstream silinmiş ("gone").
    public var upstreamGone: Bool
    public var date: Date
    public var id: String { (isRemote ? "R:" : "L:") + name }
    public init(name: String, isRemote: Bool, isHead: Bool, commit: String, upstream: String? = nil,
                ahead: Int = 0, behind: Int = 0, upstreamGone: Bool = false, date: Date) {
        self.name = name
        self.isRemote = isRemote
        self.isHead = isHead
        self.commit = commit
        self.upstream = upstream
        self.ahead = ahead
        self.behind = behind
        self.upstreamGone = upstreamGone
        self.date = date
    }
}

public struct TagInfo: Hashable, Identifiable, Sendable {
    public var name: String
    public var commit: String
    public var id: String { name }
    public init(name: String, commit: String) {
        self.name = name
        self.commit = commit
    }
}
