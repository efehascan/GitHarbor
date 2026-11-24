import XCTest
@testable import HarborCore

/// Ayrıştırıcı (sabit veri) ve gerçek depoda ekle / listele / kaldır / buda.
final class GitWorktreeTests: XCTestCase {
    private var base = ""

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-wt-" + UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: base, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: base)
    }

    func testParse() {
        let raw = [
            "worktree /r/app", "HEAD aaa", "branch refs/heads/main", "",
            "worktree /r/app-x", "HEAD bbb", "branch refs/heads/feature/x", "locked", "",
            "worktree /r/app-d", "HEAD ccc", "detached", "prunable gitdir file points to non-existent location", "",
        ].joined(separator: "\0")
        let list = WorktreeParser.parse(Data(raw.utf8))
        XCTAssertEqual(list.count, 3)
        XCTAssertEqual(list[0], Worktree(path: "/r/app", head: "aaa", branch: "main", isMain: true))
        XCTAssertEqual(list[1].branch, "feature/x")
        XCTAssertTrue(list[1].isLocked)
        XCTAssertFalse(list[1].isMain)
        XCTAssertNil(list[2].branch)
        XCTAssertTrue(list[2].isPrunable)
    }

    func testSuggestedPath() {
        XCTAssertEqual(WorktreeParser.suggestedPath(repo: "/a/b/app", branch: "feature/login"), "/a/b/app-feature-login")
    }

    private func git(_ args: [String], _ dir: String) throws -> String {
        String(decoding: try Git.runSync(args, in: dir), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func testAddListRemovePrune() async throws {
        let repo = base + "/app"
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        _ = try git(["init", "-q", "--initial-branch=main"], repo)
        for args in [["config", "user.name", "t"], ["config", "user.email", "t@t"], ["config", "commit.gpgsign", "false"]] {
            _ = try git(args, repo)
        }
        try "a\n".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)
        _ = try git(["add", "."], repo)
        _ = try git(["commit", "-qm", "ilk"], repo)
        _ = try git(["branch", "var-olan"], repo)

        // Yeni dal ve var olan dal
        let wtNew = WorktreeParser.suggestedPath(repo: repo, branch: "feature/yeni")
        try await Git.addWorktree(path: wtNew, branch: "feature/yeni", in: repo)
        let wtOld = base + "/app-eski"
        try await Git.addWorktree(path: wtOld, branch: "var-olan", in: repo)
        XCTAssertEqual(try git(["branch", "--show-current"], wtNew), "feature/yeni")
        XCTAssertEqual(try git(["branch", "--show-current"], wtOld), "var-olan")
        XCTAssertTrue(Git.isRepositoryRoot(wtNew))

        var list = try await Git.worktrees(in: repo)
        // İlki ana ağaç; diğerlerini git klasör yoluna göre sıralar.
        XCTAssertEqual(list.first?.branch, "main")
        XCTAssertTrue(list.first?.isMain ?? false)
        XCTAssertEqual(Set(list.dropFirst().compactMap(\.branch)), ["feature/yeni", "var-olan"])

        // Dolu klasöre eklenmez
        do {
            try await Git.addWorktree(path: wtOld, branch: "baska", in: repo)
            XCTFail("dolu klasöre eklenmemeli")
        } catch {}

        // Kirli çalışma ağacı kaldırılmaz (zorlanmaz)
        try "kirli\n".write(toFile: wtOld + "/a.txt", atomically: true, encoding: .utf8)
        do {
            try await Git.removeWorktree(path: wtOld, in: repo)
            XCTFail("kirli çalışma ağacı kaldırılmamalı")
        } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: wtOld + "/a.txt"))

        // Temiz olan kaldırılır, dalı kalır
        try await Git.removeWorktree(path: wtNew, in: repo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: wtNew))
        XCTAssertFalse(try git(["branch", "--list", "feature/yeni"], repo).isEmpty)

        // Klasörü elle silinen budanır
        try FileManager.default.removeItem(atPath: wtOld)
        list = try await Git.worktrees(in: repo)
        XCTAssertTrue(list.first { $0.branch == "var-olan" }?.isPrunable ?? false)
        try await Git.pruneWorktrees(in: repo)
        list = try await Git.worktrees(in: repo)
        XCTAssertEqual(list.count, 1)
    }
}
