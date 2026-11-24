import Foundation

/// Bir çalışma ağacı (git worktree).
public struct Worktree: Hashable, Identifiable, Sendable {
    public var path: String
    public var head: String
    /// Kısa dal adı; ayrık HEAD ya da çıplak depoda nil.
    public var branch: String?
    public var isMain: Bool
    public var isBare: Bool
    public var isLocked: Bool
    /// Klasörü silinmiş, budanabilir.
    public var isPrunable: Bool
    public var id: String { path }

    public init(path: String, head: String = "", branch: String? = nil, isMain: Bool = false,
                isBare: Bool = false, isLocked: Bool = false, isPrunable: Bool = false) {
        self.path = path
        self.head = head
        self.branch = branch
        self.isMain = isMain
        self.isBare = isBare
        self.isLocked = isLocked
        self.isPrunable = isPrunable
    }
}

public enum WorktreeParser {
    /// `git worktree list --porcelain -z` çıktısı. Kayıtlar boş alanla ayrılır; ilki ana çalışma ağacıdır.
    public static func parse(_ data: Data) -> [Worktree] {
        let fields = String(decoding: data, as: UTF8.self).components(separatedBy: "\0")
        var result: [Worktree] = []
        var current: Worktree?
        func flush() {
            if let c = current { result.append(c) }
            current = nil
        }
        for field in fields {
            if field.isEmpty { flush(); continue }
            let (key, value) = split(field)
            switch key {
            case "worktree":
                flush()
                current = Worktree(path: value, isMain: result.isEmpty)
            case "HEAD": current?.head = value
            case "branch":
                current?.branch = value.hasPrefix("refs/heads/") ? String(value.dropFirst("refs/heads/".count)) : value
            case "bare": current?.isBare = true
            case "locked": current?.isLocked = true
            case "prunable": current?.isPrunable = true
            default: break
            }
        }
        flush()
        return result
    }

    private static func split(_ field: String) -> (String, String) {
        guard let space = field.firstIndex(of: " ") else { return (field, "") }
        return (String(field[..<space]), String(field[field.index(after: space)...]))
    }

    /// Yeni çalışma ağacı için önerilen klasör: deponun yanında `<depo>-<dal>` ("/" → "-").
    public static func suggestedPath(repo: String, branch: String) -> String {
        let url = URL(fileURLWithPath: repo)
        let slug = branch.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        return url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent)-\(slug)").path
    }
}

public extension Git {
    static func worktrees(in repo: String) async throws -> [Worktree] {
        WorktreeParser.parse(try await run(["worktree", "list", "--porcelain", "-z"], in: repo))
    }

    /// Yeni çalışma ağacı. Dal yerelde varsa onu açar; yoksa `start`'tan (varsayılan HEAD) yeni dal oluşturur.
    /// Uzak dal adı verilirse ("origin/x") aynı adla izleyen yerel dal oluşturulur.
    static func addWorktree(path: String, branch: String, start: String? = nil, in repo: String) async throws {
        let name = branch.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw GitError(code: 1, message: "Dal adı boş") }
        if FileManager.default.fileExists(atPath: path),
           !((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).isEmpty {
            throw GitError(code: 1, message: "\(path) klasörü zaten var ve boş değil")
        }
        let local = (try? await run(["rev-parse", "--verify", "-q", "refs/heads/" + name], in: repo)) != nil
        if local {
            _ = try await run(["worktree", "add", "--quiet", path, name], in: repo)
            return
        }
        let remote = (try? await run(["rev-parse", "--verify", "-q", "refs/remotes/" + name], in: repo)) != nil
        if remote, let slash = name.firstIndex(of: "/") {
            let short = String(name[name.index(after: slash)...])
            _ = try await run(["worktree", "add", "--quiet", "--track", "-b", short, path, name], in: repo)
            return
        }
        _ = try await run(["worktree", "add", "--quiet", "-b", name, path] + (start.map { [$0] } ?? []), in: repo)
    }

    /// Çalışma ağacını kaldırır. Kaydedilmemiş değişiklik varsa git reddeder (zorlamaz); dal silinmez.
    static func removeWorktree(path: String, in repo: String) async throws {
        _ = try await run(["worktree", "remove", path], in: repo)
    }

    /// Klasörü silinmiş çalışma ağaçlarının kayıtlarını temizler.
    static func pruneWorktrees(in repo: String) async throws {
        _ = try await run(["worktree", "prune"], in: repo)
    }
}
