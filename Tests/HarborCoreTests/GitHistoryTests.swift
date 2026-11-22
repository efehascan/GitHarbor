import XCTest
@testable import HarborCore

/// Gerçek depoda: geçmiş, commit farkı, dal oluştur/geç/birleştir/sil, cherry-pick, revert, etiket.
final class GitHistoryTests: XCTestCase {
    private var repo = ""

    override func setUp() async throws {
        repo = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-hist-" + UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "Efe"], ["config", "user.email", "e@x"],
                     ["config", "commit.gpgsign", "false"], ["config", "tag.gpgsign", "false"]] {
            _ = try Git.runSync(args, in: repo)
        }
        try commit("a.txt", "1\n", "ilk")
        try commit("a.txt", "1\n2\n", "ikinci")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: repo)
    }

    private func commit(_ file: String, _ text: String, _ message: String) throws {
        try text.write(toFile: repo + "/" + file, atomically: true, encoding: .utf8)
        _ = try Git.runSync(["add", "-A"], in: repo)
        _ = try Git.runSync(["commit", "-q", "-m", message], in: repo)
    }

    private func read(_ file: String) throws -> String {
        try String(contentsOfFile: repo + "/" + file, encoding: .utf8)
    }

    func testLogAndCommitDiff() async throws {
        let log = try await Git.log(in: repo)
        XCTAssertEqual(log.map(\.subject), ["ikinci", "ilk"])
        XCTAssertEqual(log[0].author, "Efe")
        XCTAssertTrue(log[0].refs.contains("HEAD -> main"))
        XCTAssertEqual(log[1].parents, [])
        let page = try await Git.log(limit: 1, skip: 1, in: repo)
        XCTAssertEqual(page.map(\.subject), ["ilk"])

        let diff = try await Git.commitDiff(log[0].sha, in: repo)
        XCTAssertEqual(diff.first?.newPath, "a.txt")
        XCTAssertEqual(diff.first?.hunks.first?.lines.filter { $0.kind == .added }.map(\.text), ["2"])
        let root = try await Git.commitDiff(log[1].sha, in: repo)
        XCTAssertEqual(root.first?.isNewFile, true)
        let message = try await Git.commitMessage(log[0].sha, in: repo)
        XCTAssertEqual(message, "ikinci")
    }

    func testEmptyRepositoryLog() async throws {
        let empty = repo + "/bos"
        try FileManager.default.createDirectory(atPath: empty, withIntermediateDirectories: true)
        _ = try Git.runSync(["init", "-q"], in: empty)
        let log = try await Git.log(in: empty)
        XCTAssertEqual(log, [])
    }

    func testBranchLifecycleAndMerge() async throws {
        try await Git.createBranch("özellik", checkout: true, in: repo)
        try commit("b.txt", "b\n", "dal işi")
        var branches = try await Git.branches(in: repo)
        XCTAssertEqual(branches.first { $0.isHead }?.name, "özellik")

        try await Git.switchBranch(BranchInfo(name: "main", isRemote: false, isHead: false, commit: "", date: Date()), in: repo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo + "/b.txt"))
        try await Git.merge("özellik", in: repo)
        XCTAssertTrue(FileManager.default.fileExists(atPath: repo + "/b.txt"))

        try await Git.renameBranch("özellik", to: "bitti", in: repo)
        try await Git.deleteBranch("bitti", force: false, in: repo)
        branches = try await Git.branches(in: repo)
        XCTAssertEqual(branches.map(\.name), ["main"])
    }

    func testDeleteUnmergedNeedsForce() async throws {
        try await Git.createBranch("yarım", checkout: true, in: repo)
        try commit("c.txt", "c\n", "yarım iş")
        _ = try Git.runSync(["switch", "-q", "main"], in: repo)
        do {
            try await Git.deleteBranch("yarım", force: false, in: repo)
            XCTFail("birleştirilmemiş dal silinmemeli")
        } catch {}
        try await Git.deleteBranch("yarım", force: true, in: repo)
    }

    func testCherryPickRevertAndTags() async throws {
        try await Git.createBranch("yan", checkout: true, in: repo)
        try commit("d.txt", "d\n", "alınacak")
        let picked = try await Git.log(limit: 1, in: repo)[0]
        _ = try Git.runSync(["switch", "-q", "main"], in: repo)
        try await Git.cherryPick(picked.sha, in: repo)
        XCTAssertEqual(try read("d.txt"), "d\n")

        let head = try await Git.log(limit: 1, in: repo)[0]
        try await Git.revert(head, in: repo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo + "/d.txt"))
        let top = try await Git.log(limit: 1, in: repo)[0]
        XCTAssertTrue(top.subject.hasPrefix("Revert"))

        try await Git.createTag("v1.0", at: head.sha, message: "sürüm", in: repo)
        try await Git.createTag("hafif", at: top.sha, message: nil, in: repo)
        let tags = try await Git.tags(in: repo)
        XCTAssertEqual(Set(tags), [TagInfo(name: "v1.0", commit: head.sha), TagInfo(name: "hafif", commit: top.sha)])
        try await Git.deleteTag("hafif", in: repo)
        let after = try await Git.tags(in: repo)
        XCTAssertEqual(after.map(\.name), ["v1.0"])

        try await Git.checkout(commit: head.sha, in: repo)
        let status = try await Git.status(in: repo)
        XCTAssertNil(status.branch)
    }
}
