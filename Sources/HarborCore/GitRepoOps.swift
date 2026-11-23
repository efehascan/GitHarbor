import Foundation

/// Depo düzeyi işlemler: klonla, yeni depo, yayınla, son commit'i geri al, commit'e dön, yok say, kimlik.
public extension Git {
    // MARK: - Klonla ve oluştur

    /// `url`'yi `parent/<ad>` klasörüne klonlar; klasörün yolunu döndürür. Hedef doluysa hata.
    static func clone(_ url: String, into parent: String, name: String? = nil) async throws -> String {
        guard let folder = name ?? RepoHelpers.cloneFolderName(url) else {
            throw GitError(code: 1, message: "Adresten klasör adı çıkarılamadı")
        }
        let target = URL(fileURLWithPath: parent).appendingPathComponent(folder).path
        if FileManager.default.fileExists(atPath: target),
           !((try? FileManager.default.contentsOfDirectory(atPath: target)) ?? []).isEmpty {
            throw GitError(code: 1, message: "\(folder) klasörü zaten var ve boş değil")
        }
        try FileManager.default.createDirectory(atPath: parent, withIntermediateDirectories: true)
        _ = try await run(["clone", "--quiet", url.trimmingCharacters(in: .whitespacesAndNewlines), target], in: parent)
        return target
    }

    struct NewRepoOptions: Sendable {
        public var readme: Bool
        public var gitignore: String?
        public var license: String?
        public var owner: String
        public init(readme: Bool = true, gitignore: String? = nil, license: String? = nil, owner: String = "") {
            self.readme = readme
            self.gitignore = gitignore
            self.license = license
            self.owner = owner
        }
    }

    /// `parent/name` içinde yeni depo: git init (main), isteğe bağlı README, .gitignore, MIT lisansı, ilk commit.
    static func createRepository(name: String, in parent: String, options: NewRepoOptions) async throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !clean.contains("/") else { throw GitError(code: 1, message: "Geçersiz depo adı") }
        let dir = URL(fileURLWithPath: parent).appendingPathComponent(clean)
        if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
            throw GitError(code: 1, message: "\(clean) zaten bir depo")
        }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = try await run(["init", "--quiet", "--initial-branch=main"], in: dir.path)
        var files: [String] = []
        if options.readme {
            try "# \(clean)\n".write(to: dir.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
            files.append("README.md")
        }
        if let template = options.gitignore, let body = GitignoreTemplates.all[template] {
            try body.write(to: dir.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
            files.append(".gitignore")
        }
        if options.license == "MIT" {
            let year = Calendar.current.component(.year, from: Date())
            try GitignoreTemplates.mit(year: year, owner: options.owner)
                .write(to: dir.appendingPathComponent("LICENSE"), atomically: true, encoding: .utf8)
            files.append("LICENSE")
        }
        if !files.isEmpty {
            _ = try await run(["add", "--"] + files, in: dir.path)
            _ = try await run(["commit", "--quiet", "-m", "İlk commit"], in: dir.path)
        }
        return dir.path
    }

    /// `origin` ekler (yoksa) ve mevcut dalı yayınlar.
    static func publish(remoteURL: String, branch: String, in repo: String) async throws {
        if await remotes(in: repo).contains("origin") {
            _ = try await run(["remote", "set-url", "origin", remoteURL], in: repo)
        } else {
            _ = try await run(["remote", "add", "origin", remoteURL], in: repo)
        }
        _ = try await run(["push", "--quiet", "--set-upstream", "origin", branch], in: repo)
    }

    // MARK: - Geri alma

    /// Son commit'i geri alır, değişiklikleri sahnede bırakır (git reset --soft HEAD~1). İlk commit geri alınamaz.
    static func undoLastCommit(in repo: String) async throws {
        guard (try? await run(["rev-parse", "--verify", "-q", "HEAD~1"], in: repo)) != nil else {
            throw GitError(code: 1, message: "İlk commit geri alınamaz")
        }
        _ = try await run(["reset", "--soft", "HEAD~1"], in: repo)
    }

    /// Dalı bir commit'e döndürür; sonraki commit'lerin değişiklikleri çalışma klasöründe kalır (reset --mixed).
    /// Hiçbir dosya silinmez.
    static func resetKeepingChanges(to sha: String, in repo: String) async throws {
        _ = try await run(["reset", "--mixed", "--quiet", sha], in: repo)
    }

    /// Son commit gönderilmiş mi (upstream'de var mı)? Gönderilmişse geri almak geçmişi yeniden yazar.
    static func isPushed(_ sha: String, in repo: String) async -> Bool {
        guard let data = try? await run(["branch", "-r", "--contains", sha], in: repo) else { return false }
        return !String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Yok say, kimlik

    static func ignore(_ pattern: String, in repo: String) async throws {
        let url = URL(fileURLWithPath: repo).appendingPathComponent(".gitignore")
        let current = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let updated = RepoHelpers.addIgnore(pattern, to: current)
        if updated != current { try updated.write(to: url, atomically: true, encoding: .utf8) }
    }

    /// Genel git kimliği (user.name, user.email).
    static func identity() async -> (name: String, email: String) {
        let home = NSHomeDirectory()
        func value(_ key: String) async -> String {
            guard let d = try? await run(["config", "--global", "--get", key], in: home) else { return "" }
            return String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (await value("user.name"), await value("user.email"))
    }

    static func setIdentity(name: String, email: String) async throws {
        let home = NSHomeDirectory()
        _ = try await run(["config", "--global", "user.name", name], in: home)
        _ = try await run(["config", "--global", "user.email", email], in: home)
    }
}

/// Yeni depo şablonları.
public enum GitignoreTemplates {
    public static let all: [String: String] = [
        "Swift": ".DS_Store\n.build/\n.swiftpm/\nDerivedData/\n*.xcuserstate\nxcuserdata/\ndist/\n",
        "Node": ".DS_Store\nnode_modules/\n.next/\ndist/\nbuild/\n.env\n.env.local\nnpm-debug.log*\n",
        "Python": ".DS_Store\n__pycache__/\n*.pyc\n.venv/\nvenv/\n.env\ndist/\n*.egg-info/\n",
        "macOS": ".DS_Store\n.AppleDouble\n.LSOverride\n",
    ]

    public static func mit(year: Int, owner: String) -> String {
        """
        MIT License

        Copyright (c) \(year) \(owner)

        Permission is hereby granted, free of charge, to any person obtaining a copy
        of this software and associated documentation files (the "Software"), to deal
        in the Software without restriction, including without limitation the rights
        to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        copies of the Software, and to permit persons to whom the Software is
        furnished to do so, subject to the following conditions:

        The above copyright notice and this permission notice shall be included in all
        copies or substantial portions of the Software.

        THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        SOFTWARE.

        """
    }
}
