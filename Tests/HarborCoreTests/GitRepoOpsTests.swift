import XCTest
@testable import HarborCore

/// Gerçek depolarla: klonla, yeni depo, yayınla (yerel bare uzağa), son commit'i geri al, commit'e dön, yok say.
final class GitRepoOpsTests: XCTestCase {
    private var base = ""

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-repo-" + UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: base)
    }

    private func configure(_ dir: String) throws {
        for args in [["config", "user.name", "t"], ["config", "user.email", "t@t"], ["config", "commit.gpgsign", "false"]] {
            _ = try Git.runSync(args, in: dir)
        }
    }

    private func git(_ args: [String], _ dir: String) throws -> String {
        String(decoding: try Git.runSync(args, in: dir), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testCreatePublishCloneUndoReset() async throws {
        // Yeni depo: README + .gitignore + MIT, ilk commit
        setenv("GIT_AUTHOR_NAME", "t", 1); setenv("GIT_AUTHOR_EMAIL", "t@t", 1)
        setenv("GIT_COMMITTER_NAME", "t", 1); setenv("GIT_COMMITTER_EMAIL", "t@t", 1)
        let repo = try await Git.createRepository(name: "Yeni Proje", in: base,
                                                  options: .init(readme: true, gitignore: "Swift", license: "MIT", owner: "Efe"))
        try configure(repo)
        XCTAssertEqual(try git(["ls-files"], repo).split(separator: "\n").sorted(), [".gitignore", "LICENSE", "README.md"])
        XCTAssertTrue(try String(contentsOfFile: repo + "/LICENSE", encoding: .utf8).contains("Efe"))
        do {
            _ = try await Git.createRepository(name: "Yeni Proje", in: base, options: .init())
            XCTFail("var olan depo yeniden oluşturulmamalı")
        } catch {}

        // Yayınla: yerel bare uzağa
        let remote = base + "/uzak.git"
        _ = try Git.runSync(["init", "-q", "--bare", remote], in: base)
        try await Git.publish(remoteURL: remote, branch: "main", in: repo)
        let published = try await Git.status(in: repo)
        XCTAssertEqual(published.upstream, "origin/main")

        // Klonla
        let clone = try await Git.clone(remote, into: base + "/klonlar")
        XCTAssertEqual((clone as NSString).lastPathComponent, "uzak")
        XCTAssertTrue(FileManager.default.fileExists(atPath: clone + "/README.md"))
        do {
            _ = try await Git.clone(remote, into: base + "/klonlar")
            XCTFail("dolu klasöre klonlanmamalı")
        } catch {}

        // İlk commit geri alınamaz
        do {
            try await Git.undoLastCommit(in: repo)
            XCTFail("ilk commit geri alınmamalı")
        } catch {}

        // İki commit ekle, sonuncuyu geri al: değişiklik sahnede kalır
        try "a\n".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)
        _ = try Git.runSync(["add", "a.txt"], in: repo); _ = try Git.runSync(["commit", "-q", "-m", "a"], in: repo)
        let first = try git(["rev-parse", "HEAD"], repo)
        try "b\n".write(toFile: repo + "/b.txt", atomically: true, encoding: .utf8)
        _ = try Git.runSync(["add", "b.txt"], in: repo); _ = try Git.runSync(["commit", "-q", "-m", "b"], in: repo)
        try await Git.undoLastCommit(in: repo)
        XCTAssertEqual(try git(["rev-parse", "HEAD"], repo), first)
        let afterUndo = try await Git.status(in: repo)
        XCTAssertEqual(afterUndo.changes, [FileChange(path: "b.txt", kind: .added, staged: true)])

        // Commit'e dön: sonraki değişiklikler çalışma klasöründe kalır, dosya silinmez
        _ = try Git.runSync(["commit", "-q", "-m", "b tekrar"], in: repo)
        let root = try git(["rev-list", "--max-parents=0", "HEAD"], repo)
        let pushedFirst = await Git.isPushed(root, in: repo)
        XCTAssertTrue(pushedFirst)
        let notPushed = await Git.isPushed(try git(["rev-parse", "HEAD"], repo), in: repo)
        XCTAssertFalse(notPushed)
        try await Git.resetKeepingChanges(to: root, in: repo)
        XCTAssertEqual(try git(["rev-parse", "HEAD"], repo), root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo + "/a.txt"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo + "/b.txt"))

        // Yok say
        try await Git.ignore("*.txt", in: repo)
        try await Git.ignore("*.txt", in: repo)
        let ignore = try String(contentsOfFile: repo + "/.gitignore", encoding: .utf8)
        XCTAssertEqual(ignore.components(separatedBy: "\n").filter { $0 == "*.txt" }.count, 1)
        let afterIgnore = try await Git.status(in: repo)
        XCTAssertFalse(afterIgnore.changes.contains { $0.path.hasSuffix(".txt") }, "\(afterIgnore.changes)")
    }

    func testDecodeRepositories() throws {
        let json = """
        [{"id": 1, "name": "PulseBar", "full_name": "efehascan/PulseBar", "private": false, "description": null,
          "clone_url": "https://github.com/efehascan/PulseBar.git", "ssh_url": "git@github.com:efehascan/PulseBar.git",
          "html_url": "https://github.com/efehascan/PulseBar", "updated_at": "2026-11-20T10:00:00Z"}]
        """
        let repos = try GitHubAPI.decoder.decode([GitHubRepository].self, from: Data(json.utf8))
        XCTAssertEqual(repos.first?.fullName, "efehascan/PulseBar")
        XCTAssertEqual(repos.first?.isPrivate, false)
    }
}
