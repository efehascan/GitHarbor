import XCTest
@testable import HarborCore

/// Gerçek "uzak" depo (yerel bare) ile: fetch, ileri sarma, push/yayınla, çakışma ve çözümü.
final class GitSyncTests: XCTestCase {
    private var base = ""
    private var remote = "", me = "", other = ""

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-sync-" + UUID().uuidString).path
        remote = base + "/remote.git"; me = base + "/me"; other = base + "/other"
        try FileManager.default.createDirectory(atPath: remote, withIntermediateDirectories: true)
        _ = try Git.runSync(["init", "-q", "--bare", "-b", "main"], in: remote)
        for dir in [me, other] {
            _ = try Git.runSync(["clone", "-q", remote, dir], in: base)
            for args in [["config", "user.name", "t"], ["config", "user.email", "t@t"], ["config", "commit.gpgsign", "false"],
                         ["checkout", "-q", "-b", "main"]] {
                _ = try? Git.runSync(args, in: dir)
            }
        }
        try commit(in: me, file: "a.txt", "1\n", "ilk")
        _ = try Git.runSync(["push", "-q", "-u", "origin", "main"], in: me)
        _ = try Git.runSync(["pull", "-q", "origin", "main"], in: other)
        _ = try Git.runSync(["branch", "-q", "--set-upstream-to=origin/main"], in: other)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: base)
    }

    private func commit(in dir: String, file: String, _ text: String, _ message: String) throws {
        try text.write(toFile: dir + "/" + file, atomically: true, encoding: .utf8)
        _ = try Git.runSync(["add", "-A"], in: dir)
        _ = try Git.runSync(["commit", "-q", "-m", message], in: dir)
    }

    func testFetchFastForwardAndPush() async throws {
        try commit(in: other, file: "b.txt", "x\n", "başkası")
        _ = try Git.runSync(["push", "-q"], in: other)

        try await Git.fetch(in: me)
        var s = try await Git.status(in: me)
        XCTAssertEqual(s.behind, 1)
        let decision = AutoSyncPolicy.decide(status: s, operation: await Git.operation(in: me), settings: SyncSettings())
        XCTAssertEqual(decision, .fastForward)
        try await Git.fastForward(in: me)
        s = try await Git.status(in: me)
        XCTAssertEqual(s.behind, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: me + "/b.txt"))

        try commit(in: me, file: "c.txt", "y\n", "benim")
        try await Git.push(branch: "main", hasUpstream: true, in: me)
        s = try await Git.status(in: me)
        XCTAssertEqual(s.ahead, 0)
    }

    func testPublishNewBranch() async throws {
        _ = try Git.runSync(["checkout", "-q", "-b", "yeni-dal"], in: me)
        try commit(in: me, file: "d.txt", "z\n", "dal")
        try await Git.push(branch: "yeni-dal", hasUpstream: false, in: me)
        let s = try await Git.status(in: me)
        XCTAssertEqual(s.upstream, "origin/yeni-dal")
    }

    func testConflictResolveAndContinue() async throws {
        try commit(in: other, file: "a.txt", "onlar\n", "onlar")
        _ = try Git.runSync(["push", "-q"], in: other)
        try commit(in: me, file: "a.txt", "ben\n", "ben")

        do {
            try await Git.pull(mode: .merge, in: me)
            XCTFail("çakışma bekleniyordu")
        } catch {}
        let opDuring = await Git.operation(in: me)
        XCTAssertEqual(opDuring, .merge)
        let s = try await Git.status(in: me)
        XCTAssertEqual(s.changes, [FileChange(path: "a.txt", kind: .conflicted, staged: false)])

        try await Git.resolve("a.txt", take: .theirs, in: me)
        try await Git.continueOperation(.merge, in: me)
        let opAfter = await Git.operation(in: me)
        XCTAssertEqual(opAfter, .none)
        XCTAssertEqual(try String(contentsOfFile: me + "/a.txt", encoding: .utf8), "onlar\n")
        let after = try await Git.status(in: me)
        XCTAssertEqual(after.ahead, 2, "kendi commit'im + birleştirme commit'i")
    }

    func testAbortMerge() async throws {
        try commit(in: other, file: "a.txt", "onlar\n", "onlar")
        _ = try Git.runSync(["push", "-q"], in: other)
        try commit(in: me, file: "a.txt", "ben\n", "ben")
        try? await Git.pull(mode: .merge, in: me)
        try await Git.abort(.merge, in: me)
        let op = await Git.operation(in: me)
        XCTAssertEqual(op, .none)
        XCTAssertEqual(try String(contentsOfFile: me + "/a.txt", encoding: .utf8), "ben\n")
    }
}
