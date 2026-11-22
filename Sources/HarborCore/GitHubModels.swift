import Foundation

/// GitHub'daki depo kimliği.
public struct GitHubRepoID: Hashable, Sendable {
    public var owner: String
    public var name: String
    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }
    public var slug: String { owner + "/" + name }
    public var webURL: URL? { URL(string: "https://github.com/\(owner)/\(name)") }
}

public struct GitHubUser: Codable, Hashable, Sendable {
    public var login: String
    public var avatarURL: String?
    enum CodingKeys: String, CodingKey { case login, avatarURL = "avatar_url" }
    public init(login: String, avatarURL: String? = nil) {
        self.login = login
        self.avatarURL = avatarURL
    }
}

public struct PullRequestRef: Codable, Hashable, Sendable {
    /// Dal adı.
    public var ref: String
    public var sha: String
    /// Dalın bulunduğu depo ("owner/name"); fork silinmişse nil.
    public var repoFullName: String?
    enum CodingKeys: String, CodingKey { case ref, sha, repo }
    enum RepoKeys: String, CodingKey { case fullName = "full_name" }
    public init(ref: String, sha: String, repoFullName: String?) {
        self.ref = ref
        self.sha = sha
        self.repoFullName = repoFullName
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ref = try c.decode(String.self, forKey: .ref)
        sha = try c.decode(String.self, forKey: .sha)
        let repo = try? c.nestedContainer(keyedBy: RepoKeys.self, forKey: .repo)
        repoFullName = try repo?.decodeIfPresent(String.self, forKey: .fullName)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ref, forKey: .ref)
        try c.encode(sha, forKey: .sha)
    }
}

public struct PullRequest: Codable, Hashable, Identifiable, Sendable {
    public var number: Int
    public var title: String
    public var body: String?
    public var user: GitHubUser
    public var draft: Bool
    public var htmlURL: String
    public var updatedAt: Date
    public var head: PullRequestRef
    public var base: PullRequestRef
    public var id: Int { number }
    enum CodingKeys: String, CodingKey {
        case number, title, body, user, draft, head, base
        case htmlURL = "html_url", updatedAt = "updated_at"
    }
    public init(number: Int, title: String, body: String?, user: GitHubUser, draft: Bool, htmlURL: String,
                updatedAt: Date, head: PullRequestRef, base: PullRequestRef) {
        self.number = number
        self.title = title
        self.body = body
        self.user = user
        self.draft = draft
        self.htmlURL = htmlURL
        self.updatedAt = updatedAt
        self.head = head
        self.base = base
    }
}

/// Tek bir CI kontrolü (GitHub check run).
public struct CheckRun: Codable, Hashable, Identifiable, Sendable {
    public var id: Int
    public var name: String
    /// "queued", "in_progress", "completed"
    public var status: String
    /// Tamamlandıysa: "success", "failure", "neutral", "cancelled", "skipped", "timed_out", "action_required", "stale"
    public var conclusion: String?
    public var htmlURL: String?
    enum CodingKeys: String, CodingKey { case id, name, status, conclusion, htmlURL = "html_url" }
    public init(id: Int, name: String, status: String, conclusion: String?, htmlURL: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.htmlURL = htmlURL
    }
}

/// Bir commit'in kontrollerinin özeti.
public enum CheckSummary: Hashable, Sendable {
    case none
    case pending(done: Int, total: Int)
    case success(total: Int)
    case failure(failed: Int, total: Int)
}
