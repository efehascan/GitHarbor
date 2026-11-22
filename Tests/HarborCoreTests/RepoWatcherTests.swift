import XCTest
@testable import HarborCore

final class RepoWatcherTests: XCTestCase {
    func testAffectedRootsFiltersGitNoise() {
        let roots = ["/r/a", "/r/ab"]
        XCTAssertEqual(RepoWatcher.affectedRoots(["/r/a/src/x.swift"], roots: roots), ["/r/a"])
        XCTAssertEqual(RepoWatcher.affectedRoots(["/r/ab/readme"], roots: roots), ["/r/ab"], "önek benzerliği karışmasın")
        XCTAssertEqual(RepoWatcher.affectedRoots(["/r/a/.git/objects/12/abc", "/r/a/.git/index.lock", "/r/a/.git/logs/HEAD"], roots: roots), [])
        XCTAssertEqual(RepoWatcher.affectedRoots(["/r/a/.git/index"], roots: roots), ["/r/a"])
        XCTAssertEqual(RepoWatcher.affectedRoots(["/r/a/.git/refs/heads/main"], roots: roots), ["/r/a"])
        XCTAssertEqual(RepoWatcher.affectedRoots(["/elsewhere/x"], roots: roots), [])
    }

    func testDiscoverFindsRootAndChildren() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-disc-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        for name in ["b-repo", "a-repo"] {
            let dir = base.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            _ = try Git.runSync(["init", "-q"], in: dir.path)
        }
        try FileManager.default.createDirectory(at: base.appendingPathComponent("plain"), withIntermediateDirectories: true)
        let found = HarborStore.discover([base])
        XCTAssertEqual(found.map { ($0 as NSString).lastPathComponent }, ["a-repo", "b-repo"])
        XCTAssertEqual(HarborStore.discover([base.appendingPathComponent("a-repo")]).count, 1)
    }
}
