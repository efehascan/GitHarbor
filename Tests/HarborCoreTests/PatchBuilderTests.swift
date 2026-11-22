import XCTest
@testable import HarborCore

final class PatchBuilderTests: XCTestCase {
    /// a,b,c,d,e → a,B,c,D,e,f (b→B, d→D, f eklendi)
    private let file = FileDiff(oldPath: "x.txt", newPath: "x.txt", header: ["diff --git a/x.txt b/x.txt"], hunks: [
        DiffHunk(oldStart: 1, oldCount: 5, newStart: 1, newCount: 6, lines: [
            DiffLine(kind: .context, text: "a", oldNumber: 1, newNumber: 1),
            DiffLine(kind: .removed, text: "b", oldNumber: 2),
            DiffLine(kind: .added, text: "B", newNumber: 2),
            DiffLine(kind: .context, text: "c", oldNumber: 3, newNumber: 3),
            DiffLine(kind: .removed, text: "d", oldNumber: 4),
            DiffLine(kind: .added, text: "D", newNumber: 4),
            DiffLine(kind: .context, text: "e", oldNumber: 5, newNumber: 5),
            DiffLine(kind: .added, text: "f", newNumber: 6),
        ]),
    ])

    func testForwardKeepsOnlySelection() {
        let p = PatchBuilder.patch(for: file, selecting: [DiffLineRef(hunk: 0, line: 1), DiffLineRef(hunk: 0, line: 2)], direction: .forward)
        XCTAssertEqual(p, """
        diff --git a/x.txt b/x.txt
        --- a/x.txt
        +++ b/x.txt
        @@ -1,5 +1,5 @@
         a
        -b
        +B
         c
         d
         e

        """)
    }

    func testReverseTurnsUnselectedAdditionsIntoContext() {
        let p = PatchBuilder.patch(for: file, selecting: [DiffLineRef(hunk: 0, line: 7)], direction: .reverse)
        XCTAssertEqual(p, """
        diff --git a/x.txt b/x.txt
        --- a/x.txt
        +++ b/x.txt
        @@ -1,5 +1,6 @@
         a
         B
         c
         D
         e
        +f

        """)
    }

    func testNoChangeSelectedGivesNil() {
        XCTAssertNil(PatchBuilder.patch(for: file, selecting: [DiffLineRef(hunk: 0, line: 0)], direction: .forward))
        XCTAssertNil(PatchBuilder.patch(for: FileDiff(isBinary: true), selecting: [], direction: .forward))
        XCTAssertEqual(PatchBuilder.changeRefs(in: file).count, 5)
    }
}

/// Gerçek depoda: satır seçerek sahneye ekleme, çıkarma, geri alma; commit, amend, stash.
final class GitOperationsTests: XCTestCase {
    private var repo = ""

    override func setUp() async throws {
        repo = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-ops-" + UUID().uuidString).path
        try FileManager.default.createDirectory(atPath: repo, withIntermediateDirectories: true)
        for args in [["init", "-q", "-b", "main"], ["config", "user.name", "t"], ["config", "user.email", "t@t"],
                     ["config", "commit.gpgsign", "false"]] {
            _ = try Git.runSync(args, in: repo)
        }
        try write("x.txt", "a\nb\nc\nd\ne\n")
        try await Git.stage(["x.txt"], in: repo)
        try await Git.commit(message: "ilk", amend: false, in: repo)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: repo)
    }

    private func write(_ name: String, _ text: String) throws {
        try text.write(toFile: repo + "/" + name, atomically: true, encoding: .utf8)
    }

    private func read(_ name: String) throws -> String {
        try String(contentsOfFile: repo + "/" + name, encoding: .utf8)
    }

    private func git(_ args: [String]) throws -> String {
        String(decoding: try Git.runSync(args, in: repo), as: UTF8.self)
    }

    /// Fark satırını metniyle bulur.
    private func ref(_ diff: FileDiff, _ kind: DiffLineKind, _ text: String) -> DiffLineRef? {
        for (h, hunk) in diff.hunks.enumerated() {
            if let i = hunk.lines.firstIndex(where: { $0.kind == kind && $0.text == text }) { return DiffLineRef(hunk: h, line: i) }
        }
        return nil
    }

    func testStageUnstageAndDiscardSelectedLines() async throws {
        try write("x.txt", "a\nB\nc\nD\ne\nf\n")
        let work = try await XCTUnwrapAsync(await Git.diff(path: "x.txt", staged: false, untracked: false, in: repo))
        let sel: Set<DiffLineRef> = [try XCTUnwrap(ref(work, .removed, "b")), try XCTUnwrap(ref(work, .added, "B"))]

        // Sadece b→B sahneye
        try await Git.apply(patch: try XCTUnwrap(PatchBuilder.patch(for: work, selecting: sel, direction: .forward)),
                            cached: true, reverse: false, in: repo)
        XCTAssertEqual(try git(["show", ":x.txt"]), "a\nB\nc\nd\ne\n")
        XCTAssertEqual(try read("x.txt"), "a\nB\nc\nD\ne\nf\n", "çalışma klasörü değişmemeli")

        // Sahnedekinden geri çıkar
        let staged = try await XCTUnwrapAsync(await Git.diff(path: "x.txt", staged: true, untracked: false, in: repo))
        try await Git.apply(patch: try XCTUnwrap(PatchBuilder.patch(for: staged, selecting: PatchBuilder.changeRefs(in: staged), direction: .reverse)),
                            cached: true, reverse: true, in: repo)
        XCTAssertEqual(try git(["show", ":x.txt"]), "a\nb\nc\nd\ne\n")

        // Çalışma klasöründe sadece eklenen f satırını geri al
        let again = try await XCTUnwrapAsync(await Git.diff(path: "x.txt", staged: false, untracked: false, in: repo))
        try await Git.apply(patch: try XCTUnwrap(PatchBuilder.patch(for: again, selecting: [try XCTUnwrap(ref(again, .added, "f"))], direction: .reverse)),
                            cached: false, reverse: true, in: repo)
        XCTAssertEqual(try read("x.txt"), "a\nB\nc\nD\ne\n")
    }

    func testUntrackedDiffStageAndDiscardToTrash() async throws {
        try write("yeni dosya.txt", "bir\niki\n")
        let d = try await XCTUnwrapAsync(await Git.diff(path: "yeni dosya.txt", staged: false, untracked: true, in: repo))
        XCTAssertTrue(d.isNewFile)
        XCTAssertEqual(d.hunks.first?.lines.map(\.text), ["bir", "iki"])
        try await Git.stage(["yeni dosya.txt"], in: repo)
        let afterStage = try await Git.status(in: repo)
        XCTAssertEqual(afterStage.changes, [FileChange(path: "yeni dosya.txt", kind: .added, staged: true)])
        try await Git.unstage(["yeni dosya.txt"], in: repo)
        try await Git.discard(tracked: [], untracked: ["yeni dosya.txt"], in: repo)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repo + "/yeni dosya.txt"))
    }

    func testCommitAmendAndStash() async throws {
        try write("x.txt", "değişti\n")
        try await Git.stage(["x.txt"], in: repo)
        try await Git.commit(message: "İkinci\n\nAyrıntı", amend: false, in: repo)
        let last = await Git.lastCommitMessage(in: repo)
        XCTAssertEqual(last, "İkinci\n\nAyrıntı")
        try await Git.commit(message: "İkinci (düzeltildi)", amend: true, in: repo)
        XCTAssertEqual(try git(["rev-list", "--count", "HEAD"]).trimmingCharacters(in: .whitespacesAndNewlines), "2")

        try write("x.txt", "saklanacak\n")
        try write("u.txt", "izlenmeyen\n")
        try await Git.stashPush(message: "deneme", includeUntracked: true, in: repo)
        let afterStash = try await Git.status(in: repo)
        XCTAssertTrue(afterStash.isClean)
        let list = try await Git.stashes(in: repo)
        XCTAssertEqual(list.map(\.ref), ["stash@{0}"])
        XCTAssertTrue(list[0].message.hasSuffix("deneme"))
        try await Git.stashApply("stash@{0}", pop: true, in: repo)
        XCTAssertEqual(try read("x.txt"), "saklanacak\n")
        XCTAssertEqual(try read("u.txt"), "izlenmeyen\n")
        let remaining = try await Git.stashes(in: repo)
        XCTAssertEqual(remaining, [])
    }
}

func XCTUnwrapAsync<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) async throws -> T {
    try XCTUnwrap(value, file: file, line: line)
}
