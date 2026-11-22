import Foundation

/// Uzak depo işlemleri ve çakışma çözümü. Kimlik doğrulama git'in kendi yardımcılarıyla
/// (osxkeychain, ssh-agent) yapılır; etkileşimli istem kapalıdır.
public extension Git {
    // MARK: - Uzak

    static func remotes(in repo: String) async -> [String] {
        guard let data = try? await run(["remote"], in: repo) else { return [] }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init)
    }

    /// Bütün uzakları getirir, silinmiş uzak dalları budar.
    static func fetch(in repo: String) async throws {
        _ = try await run(["fetch", "--all", "--prune", "--quiet"], in: repo)
    }

    /// Yalnızca ileri sarma (güvenli: yerel commit ya da çakışma yaratmaz).
    static func fastForward(in repo: String) async throws {
        _ = try await run(["merge", "--ff-only", "--quiet", "@{u}"], in: repo)
    }

    enum PullMode: String, Sendable, CaseIterable {
        case merge, rebase
    }

    /// Pull: ileri sarılabiliyorsa ileri sarar; dallar ayrıştıysa seçilen yöntemle birleştirir.
    static func pull(mode: PullMode, in repo: String) async throws {
        _ = try await run(["pull", "--quiet", "--no-edit", mode == .rebase ? "--rebase" : "--no-rebase"], in: repo)
    }

    /// Push. Dalın upstream'i yoksa `origin`'e (yoksa ilk uzağa) yayınlar ve upstream'i ayarlar.
    static func push(branch: String, hasUpstream: Bool, in repo: String) async throws {
        if hasUpstream {
            _ = try await run(["push", "--quiet"], in: repo)
        } else {
            let all = await remotes(in: repo)
            guard let remote = all.contains("origin") ? "origin" : all.first else {
                throw GitError(code: 1, message: "Bu depoda uzak (remote) yok")
            }
            _ = try await run(["push", "--quiet", "--set-upstream", remote, branch], in: repo)
        }
    }

    // MARK: - Süren işlem ve çakışma

    static func operation(in repo: String) async -> RepoOperation {
        func exists(_ name: String) async -> Bool {
            guard let data = try? await run(["rev-parse", "--git-path", name], in: repo) else { return false }
            let rel = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let path = rel.hasPrefix("/") ? rel : repo + "/" + rel
            return FileManager.default.fileExists(atPath: path)
        }
        let rebaseMerge = await exists("rebase-merge")
        let rebaseApply = await exists("rebase-apply")
        if rebaseMerge || rebaseApply { return .rebase }
        if await exists("MERGE_HEAD") { return .merge }
        if await exists("CHERRY_PICK_HEAD") { return .cherryPick }
        if await exists("REVERT_HEAD") { return .revert }
        return .none
    }

    enum ConflictSide: Sendable { case ours, theirs }

    /// Çakışan dosyada bir tarafı seçer ve dosyayı çözüldü olarak işaretler.
    static func resolve(_ path: String, take side: ConflictSide, in repo: String) async throws {
        _ = try await run(["checkout", side == .ours ? "--ours" : "--theirs", "--", path], in: repo)
        _ = try await run(["add", "--", path], in: repo)
    }

    /// Elle düzenlenmiş dosyayı çözüldü olarak işaretler.
    static func markResolved(_ path: String, in repo: String) async throws {
        _ = try await run(["add", "--", path], in: repo)
    }

    static func abort(_ operation: RepoOperation, in repo: String) async throws {
        switch operation {
        case .merge: _ = try await run(["merge", "--abort"], in: repo)
        case .rebase: _ = try await run(["rebase", "--abort"], in: repo)
        case .cherryPick: _ = try await run(["cherry-pick", "--abort"], in: repo)
        case .revert: _ = try await run(["revert", "--abort"], in: repo)
        case .none: break
        }
    }

    /// Çakışmalar çözüldükten sonra işlemi bitirir (mesaj düzenleyicisi açılmaz).
    static func continueOperation(_ operation: RepoOperation, in repo: String) async throws {
        let noEditor = ["-c", "core.editor=true"]
        switch operation {
        case .merge: _ = try await run(["commit", "--no-edit", "--quiet"], in: repo)
        case .rebase: _ = try await run(noEditor + ["rebase", "--continue"], in: repo)
        case .cherryPick: _ = try await run(noEditor + ["cherry-pick", "--continue"], in: repo)
        case .revert: _ = try await run(noEditor + ["revert", "--continue"], in: repo)
        case .none: break
        }
    }
}
