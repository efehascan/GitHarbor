import Foundation

/// Sakla (stash) kaydı.
public struct StashEntry: Hashable, Identifiable, Sendable {
    /// "stash@{0}"
    public var ref: String
    public var message: String
    public var relativeDate: String
    public var id: String { ref }
    public init(ref: String, message: String, relativeDate: String) {
        self.ref = ref
        self.message = message
        self.relativeDate = relativeDate
    }
}

/// Değişiklikler ekranının git işlemleri. Hepsi `Git.run` ile, kabuk yok.
public extension Git {
    // MARK: - Fark

    /// Bir dosyanın farkı. İzlenmeyen dosya `--no-index` ile boş dosyaya karşı karşılaştırılır.
    /// Yeniden adlandırmada `oldPath` verilmeli: git ikisini birlikte görürse farkı yeniden adlandırma olarak gösterir.
    static func diff(path: String, oldPath: String? = nil, staged: Bool, untracked: Bool, in repo: String) async throws -> FileDiff? {
        let text: String
        if untracked {
            let data = try await run(["diff", "--no-color", "--no-ext-diff", "--no-index", "--", "/dev/null", path],
                                     in: repo, allowedExitCodes: [0, 1])
            text = String(decoding: data, as: UTF8.self)
        } else {
            var args = ["diff", "--no-color", "--no-ext-diff", "--find-renames"]
            if staged { args.append("--cached") }
            args += ["--"] + (oldPath.map { [$0] } ?? []) + [path]
            text = String(decoding: try await run(args, in: repo), as: UTF8.self)
        }
        let files = DiffParser.parse(text)
        return files.first { $0.newPath == path } ?? files.first
    }

    // MARK: - Sahne

    static func stage(_ paths: [String], in repo: String) async throws {
        guard !paths.isEmpty else { return }
        _ = try await run(["add", "-A", "--"] + paths, in: repo)
    }

    static func unstage(_ paths: [String], in repo: String) async throws {
        guard !paths.isEmpty else { return }
        if (try? await run(["rev-parse", "--verify", "-q", "HEAD"], in: repo)) != nil {
            _ = try await run(["restore", "--staged", "--"] + paths, in: repo)
        } else {
            // İlk commit öncesi: HEAD yok.
            _ = try await run(["rm", "--cached", "-r", "-q", "--"] + paths, in: repo)
        }
    }

    /// İzlenen dosyalardaki çalışma klasörü değişikliklerini geri alır. İzlenmeyen dosyalar
    /// silinmez, Çöp Sepeti'ne taşınır (geri getirilebilir).
    static func discard(tracked: [String], untracked: [String], in repo: String) async throws {
        if !tracked.isEmpty {
            _ = try await run(["restore", "--worktree", "--"] + tracked, in: repo)
        }
        for path in untracked {
            let url = URL(fileURLWithPath: repo).appendingPathComponent(path)
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    }

    /// Yamayı uygular. `cached`: sahneye; `reverse`: tersine.
    static func apply(patch: String, cached: Bool, reverse: Bool, in repo: String) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-\(UUID().uuidString).patch")
        try patch.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        var args = ["apply", "--recount", "--whitespace=nowarn"]
        if cached { args.append("--cached") }
        if reverse { args.append("--reverse") }
        args.append(file.path)
        _ = try await run(args, in: repo)
    }

    // MARK: - Commit

    static func commit(message: String, amend: Bool, in repo: String) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-msg-\(UUID().uuidString).txt")
        try message.write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }
        var args = ["commit", "-q", "--cleanup=strip", "-F", file.path]
        if amend { args.append("--amend") }
        _ = try await run(args, in: repo)
    }

    /// Son commit'in mesajı (amend için); commit yoksa nil.
    static func lastCommitMessage(in repo: String) async -> String? {
        guard let data = try? await run(["log", "-1", "--format=%B"], in: repo) else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    // MARK: - Sakla (stash)

    static func stashes(in repo: String) async throws -> [StashEntry] {
        let data = try await run(["stash", "list", "--format=%gd%x1f%s%x1f%cr"], in: repo)
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let f = line.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 3 else { return nil }
            return StashEntry(ref: f[0], message: f[1], relativeDate: f[2])
        }
    }

    static func stashPush(message: String?, includeUntracked: Bool, in repo: String) async throws {
        var args = ["stash", "push", "-q"]
        if includeUntracked { args.append("--include-untracked") }
        if let message, !message.isEmpty { args += ["-m", message] }
        _ = try await run(args, in: repo)
    }

    static func stashApply(_ ref: String, pop: Bool, in repo: String) async throws {
        _ = try await run(["stash", pop ? "pop" : "apply", "-q", "--index", ref], in: repo)
    }

    static func stashDrop(_ ref: String, in repo: String) async throws {
        _ = try await run(["stash", "drop", "-q", ref], in: repo)
    }
}
