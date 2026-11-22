import Foundation

/// Geçmiş, dallar, etiketler ve commit üzerinde işlemler.
public extension Git {
    // MARK: - Geçmiş

    /// `ref` (varsayılan HEAD) geçmişi; `skip` ile sayfalanır. Henüz commit yoksa [].
    static func log(ref: String = "HEAD", limit: Int = 200, skip: Int = 0, in repo: String) async throws -> [CommitInfo] {
        guard (try? await run(["rev-parse", "--verify", "-q", ref], in: repo)) != nil else { return [] }
        let data = try await run(["log", "--format=\(LogParser.logFormat)", "--max-count=\(limit)", "--skip=\(skip)",
                                  "--decorate=short", ref, "--"], in: repo)
        return LogParser.parseLog(String(decoding: data, as: UTF8.self))
    }

    /// Commit'in tam mesajı.
    static func commitMessage(_ sha: String, in repo: String) async throws -> String {
        let data = try await run(["show", "-s", "--format=%B", sha], in: repo)
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Commit'in dosya farkları (ilk ebeveyne göre; kök commit'te boş ağaca göre).
    static func commitDiff(_ sha: String, in repo: String) async throws -> [FileDiff] {
        let data = try await run(["show", "--format=", "--no-color", "--no-ext-diff", "--find-renames", "--first-parent", sha], in: repo)
        return DiffParser.parse(String(decoding: data, as: UTF8.self))
    }

    // MARK: - Dallar

    static func branches(in repo: String) async throws -> [BranchInfo] {
        let data = try await run(["for-each-ref", "--format=\(LogParser.branchFormat)", "--sort=-committerdate",
                                  "refs/heads", "refs/remotes"], in: repo)
        return LogParser.parseBranches(String(decoding: data, as: UTF8.self))
    }

    static func createBranch(_ name: String, from start: String? = nil, checkout: Bool, in repo: String) async throws {
        if checkout {
            _ = try await run(["switch", "-q", "-c", name] + (start.map { [$0] } ?? []), in: repo)
        } else {
            _ = try await run(["branch", "-q", name] + (start.map { [$0] } ?? []), in: repo)
        }
    }

    /// Dala geçer. Uzak dal verilirse ("origin/x") aynı adla izleyen yerel dal oluşturulur (varsa ona geçilir).
    static func switchBranch(_ branch: BranchInfo, in repo: String) async throws {
        if branch.isRemote {
            let local = branch.name.split(separator: "/", maxSplits: 1).dropFirst().first.map(String.init) ?? branch.name
            let exists = (try? await run(["rev-parse", "--verify", "-q", "refs/heads/" + local], in: repo)) != nil
            if exists {
                _ = try await run(["switch", "-q", local], in: repo)
            } else {
                _ = try await run(["switch", "-q", "--track", branch.name], in: repo)
            }
        } else {
            _ = try await run(["switch", "-q", branch.name], in: repo)
        }
    }

    static func renameBranch(_ old: String, to new: String, in repo: String) async throws {
        _ = try await run(["branch", "-q", "-m", old, new], in: repo)
    }

    /// Yerel dalı siler. `force` değilse birleştirilmemiş dal silinmez (git hata verir).
    static func deleteBranch(_ name: String, force: Bool, in repo: String) async throws {
        _ = try await run(["branch", "-q", force ? "-D" : "-d", name], in: repo)
    }

    /// Verilen dalı mevcut dala birleştirir. Çakışırsa hata atar ve birleştirme süren işlem olarak kalır.
    static func merge(_ branch: String, noFastForward: Bool = false, in repo: String) async throws {
        var args = ["merge", "--no-edit", "--quiet"]
        if noFastForward { args.append("--no-ff") }
        _ = try await run(args + [branch], in: repo)
    }

    static func rebase(onto branch: String, in repo: String) async throws {
        _ = try await run(["-c", "core.editor=true", "rebase", "--quiet", branch], in: repo)
    }

    // MARK: - Commit işlemleri

    static func cherryPick(_ sha: String, in repo: String) async throws {
        _ = try await run(["cherry-pick", sha], in: repo)
    }

    /// Commit'i geri alan yeni bir commit oluşturur (birleştirme commit'inde ilk ebeveyne göre).
    static func revert(_ commit: CommitInfo, in repo: String) async throws {
        var args = ["revert", "--no-edit"]
        if commit.isMerge { args += ["-m", "1"] }
        _ = try await run(args + [commit.sha], in: repo)
    }

    /// Ayrık HEAD: o commit'e geçer (dal değiştirmeden inceleme için).
    static func checkout(commit sha: String, in repo: String) async throws {
        _ = try await run(["switch", "-q", "--detach", sha], in: repo)
    }

    // MARK: - Etiketler

    static func tags(in repo: String) async throws -> [TagInfo] {
        let data = try await run(["for-each-ref", "--format=%(refname:short)%1f%(objectname)%1f%(*objectname)",
                                  "--sort=-creatordate", "refs/tags"], in: repo)
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3 else { return nil }
            // Açıklamalı etikette commit, soyulmuş nesnedir.
            return TagInfo(name: f[0], commit: f[2].isEmpty ? f[1] : f[2])
        }
    }

    static func createTag(_ name: String, at sha: String, message: String?, in repo: String) async throws {
        if let message, !message.isEmpty {
            _ = try await run(["tag", "-a", name, "-m", message, sha], in: repo)
        } else {
            _ = try await run(["tag", name, sha], in: repo)
        }
    }

    static func deleteTag(_ name: String, in repo: String) async throws {
        _ = try await run(["tag", "-d", name], in: repo)
    }

    /// Etiketi uzağa gönderir (`origin`, yoksa ilk uzak).
    static func pushTag(_ name: String, in repo: String) async throws {
        let all = await remotes(in: repo)
        guard let remote = all.contains("origin") ? "origin" : all.first else {
            throw GitError(code: 1, message: "Bu depoda uzak (remote) yok")
        }
        _ = try await run(["push", "--quiet", remote, "refs/tags/" + name], in: repo)
    }
}
