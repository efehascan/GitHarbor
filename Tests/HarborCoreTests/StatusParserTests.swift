import XCTest
@testable import HarborCore

final class StatusParserTests: XCTestCase {
    private func parse(_ records: [String]) -> RepoStatus {
        StatusParser.parse(Data((records.joined(separator: "\u{0}") + "\u{0}").utf8))
    }

    func testBranchHeaders() {
        let s = parse([
            "# branch.oid 1a2b3c4d5e6f",
            "# branch.head main",
            "# branch.upstream origin/main",
            "# branch.ab +2 -5",
        ])
        XCTAssertEqual(s.branch, "main")
        XCTAssertEqual(s.commit, "1a2b3c4d5e6f")
        XCTAssertEqual(s.upstream, "origin/main")
        XCTAssertEqual(s.ahead, 2)
        XCTAssertEqual(s.behind, 5)
        XCTAssertTrue(s.isClean)
    }

    func testDetachedAndInitial() {
        let d = parse(["# branch.oid 1a2b", "# branch.head (detached)"])
        XCTAssertNil(d.branch)
        XCTAssertEqual(d.commit, "1a2b")
        let i = parse(["# branch.oid (initial)", "# branch.head main"])
        XCTAssertNil(i.commit)
        XCTAssertEqual(i.branch, "main")
        XCTAssertNil(i.upstream)
        XCTAssertEqual(i.ahead, 0)
    }

    func testOrdinaryChanges() {
        let s = parse([
            "# branch.head main",
            "1 .M N... 100644 100644 100644 aaa aaa src/app.swift",
            "1 A. N... 000000 100644 100644 000 bbb new file.txt",
            "1 MD N... 100644 100644 000000 ccc ddd both.txt",
            "1 .T N... 100644 120000 120000 eee eee link",
        ])
        XCTAssertEqual(s.changes, [
            FileChange(path: "src/app.swift", kind: .modified, staged: false),
            FileChange(path: "new file.txt", kind: .added, staged: true),
            FileChange(path: "both.txt", kind: .modified, staged: true),
            FileChange(path: "both.txt", kind: .deleted, staged: false),
            FileChange(path: "link", kind: .typeChanged, staged: false),
        ])
    }

    func testRenameTakesOriginalPathFromNextRecord() {
        let s = parse([
            "# branch.head main",
            "2 R. N... 100644 100644 100644 aaa aaa R100 docs/new name.md",
            "docs/old.md",
            "? scratch/notes.txt",
        ])
        XCTAssertEqual(s.changes, [
            FileChange(path: "docs/new name.md", oldPath: "docs/old.md", kind: .renamed, staged: true),
            FileChange(path: "scratch/notes.txt", kind: .untracked, staged: false),
        ])
    }

    func testConflictAndIgnored() {
        let s = parse([
            "# branch.head feature/x",
            "u UU N... 100644 100644 100644 100644 a b c conflict.swift",
            "! build/out.o",
        ])
        XCTAssertEqual(s.branch, "feature/x")
        XCTAssertEqual(s.changes, [FileChange(path: "conflict.swift", kind: .conflicted, staged: false)])
    }

    func testEmptyAndGarbage() {
        XCTAssertEqual(StatusParser.parse(Data()), RepoStatus())
        XCTAssertEqual(parse(["xyz", "1 short"]).changes, [])
    }

    func testRealRepository() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-status-" + UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        _ = try Git.runSync(["init", "-q", "-b", "main"], in: dir)
        try "a".write(toFile: dir + "/a.txt", atomically: true, encoding: .utf8)
        _ = try Git.runSync(["add", "a.txt"], in: dir)
        _ = try Git.runSync(["-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "-m", "ilk"], in: dir)
        try "b".write(toFile: dir + "/a.txt", atomically: true, encoding: .utf8)
        try "c".write(toFile: dir + "/yeni dosya.txt", atomically: true, encoding: .utf8)
        let s = StatusParser.parse(try Git.runSync(["status", "--porcelain=v2", "--branch", "-z", "--untracked-files=all"], in: dir))
        XCTAssertEqual(s.branch, "main")
        XCTAssertNotNil(s.commit)
        XCTAssertEqual(Set(s.changes), [FileChange(path: "a.txt", kind: .modified, staged: false),
                                        FileChange(path: "yeni dosya.txt", kind: .untracked, staged: false)])
    }
}
