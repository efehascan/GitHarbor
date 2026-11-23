import Foundation
import Security

/// GitHub token'ı macOS Anahtar Zinciri'nde. Token hiçbir zaman dosyaya ya da loga yazılmaz.
public enum TokenStore {
    static let service = "com.efehascan.githarbor"
    static let account = "github.com"

    public static func load() -> String? {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    public static func save(_ token: String) -> Bool {
        delete()
        let attrs: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account, kSecValueData as String: Data(token.utf8),
                                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]
        return SecItemAdd(attrs as CFDictionary, nil) == errSecSuccess
    }

    public static func delete() {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
    }

    /// GitHub CLI (`gh`) oturumundaki token; gh yoksa ya da girişsizse nil.
    public static func tokenFromGitHubCLI() -> String? {
        for path in ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"] where FileManager.default.isExecutableFile(atPath: path) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: path)
            p.arguments = ["auth", "token", "--hostname", "github.com"]
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            p.standardInput = FileHandle.nullDevice
            guard (try? p.run()) != nil else { continue }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let token = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if p.terminationStatus == 0, !token.isEmpty { return token }
        }
        return nil
    }
}

public struct GitHubAPIError: Error, CustomStringConvertible, Sendable {
    public var status: Int
    public var message: String
    public var description: String {
        switch status {
        case 401: "GitHub girişi geçersiz ya da süresi dolmuş (401)"
        case 403: "GitHub izin vermedi (403): \(message)"
        case 404: "Bulunamadı ya da erişim yok (404)"
        case 422: "GitHub isteği reddetti: \(message)"
        default: "GitHub hatası \(status): \(message)"
        }
    }
}

/// GitHub REST API istemcisi (URLSession, dış paket yok).
public struct GitHubAPI: Sendable {
    public var token: String
    public var base = URL(string: "https://api.github.com")!

    public init(token: String) {
        self.token = token
    }

    public static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Uç noktalar

    public func currentUser() async throws -> GitHubUser {
        try await get("/user")
    }

    public func defaultBranch(_ repo: GitHubRepoID) async throws -> String {
        struct R: Decodable { let default_branch: String }
        let r: R = try await get("/repos/\(repo.slug)")
        return r.default_branch
    }

    public func pullRequests(_ repo: GitHubRepoID, state: String = "open") async throws -> [PullRequest] {
        try await get("/repos/\(repo.slug)/pulls", query: ["state": state, "per_page": "50", "sort": "updated", "direction": "desc"])
    }

    public func checkRuns(_ repo: GitHubRepoID, sha: String) async throws -> [CheckRun] {
        struct R: Decodable { let check_runs: [CheckRun] }
        let r: R = try await get("/repos/\(repo.slug)/commits/\(sha)/check-runs", query: ["per_page": "100"])
        return r.check_runs
    }

    /// Kullanıcının depoları (sahip, ortak, kuruluş üyesi); son güncellenen önce.
    public func repositories(page: Int = 1) async throws -> [GitHubRepository] {
        try await get("/user/repos", query: ["per_page": "100", "page": "\(page)", "sort": "updated",
                                             "affiliation": "owner,collaborator,organization_member"])
    }

    /// Kullanıcı hesabında yeni depo (boş; yerel depo gönderilecek).
    public func createRepository(name: String, description: String, isPrivate: Bool) async throws -> GitHubRepository {
        try await send("POST", "/user/repos", body: ["name": name, "description": description, "private": isPrivate,
                                                     "auto_init": false])
    }

    public func createPullRequest(_ repo: GitHubRepoID, title: String, body: String, head: String, base: String,
                                  draft: Bool) async throws -> PullRequest {
        try await send("POST", "/repos/\(repo.slug)/pulls",
                       body: ["title": title, "body": body, "head": head, "base": base, "draft": draft])
    }

    // MARK: - İstek

    private func request(_ method: String, _ path: String, query: [String: String] = [:]) -> URLRequest {
        var comps = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { comps?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var req = URLRequest(url: comps?.url ?? base)
        req.httpMethod = method
        req.timeoutInterval = 20
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        req.setValue("GitHarborDesktop", forHTTPHeaderField: "User-Agent")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return req
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        try await perform(request("GET", path, query: query))
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: [String: Any]) async throws -> T {
        var req = request(method, path)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(req)
    }

    private func perform<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let e = try? JSONDecoder().decode(APIErrorBody.self, from: data)
            let detail = ([e?.message] + (e?.errors ?? []).map(\.message)).compactMap { $0 }.joined(separator: " — ")
            throw GitHubAPIError(status: status, message: detail)
        }
        return try Self.decoder.decode(T.self, from: data)
    }
}

private struct APIErrorBody: Decodable {
    struct Item: Decodable { let message: String? }
    let message: String?
    let errors: [Item]?
}

public extension Git {
    /// `origin` (yoksa ilk uzak) GitHub'daysa depo kimliği.
    static func gitHubRepo(in repo: String) async -> GitHubRepoID? {
        let all = await remotes(in: repo)
        guard let remote = all.contains("origin") ? "origin" : all.first,
              let data = try? await run(["remote", "get-url", remote], in: repo) else { return nil }
        return GitHubParsing.repoID(fromRemote: String(decoding: data, as: UTF8.self))
    }

    /// PR'ı yerelde açar: aynı depodaki dalsa izleyen dala geçer; fork'taysa `pr-<no>` dalına getirir.
    static func checkoutPullRequest(_ pr: PullRequest, repoID: GitHubRepoID, in repo: String) async throws {
        let remote = (await remotes(in: repo)).contains("origin") ? "origin" : ((await remotes(in: repo)).first ?? "origin")
        if pr.head.repoFullName?.lowercased() == repoID.slug.lowercased() {
            _ = try await run(["fetch", "--quiet", remote, pr.head.ref], in: repo)
            let exists = (try? await run(["rev-parse", "--verify", "-q", "refs/heads/" + pr.head.ref], in: repo)) != nil
            if exists {
                _ = try await run(["switch", "-q", pr.head.ref], in: repo)
            } else {
                _ = try await run(["switch", "-q", "--track", "\(remote)/\(pr.head.ref)"], in: repo)
            }
        } else {
            let local = "pr-\(pr.number)"
            _ = try await run(["fetch", "--quiet", "--force", remote, "pull/\(pr.number)/head:\(local)"], in: repo)
            _ = try await run(["switch", "-q", local], in: repo)
        }
    }
}
