import XCTest
@testable import HarborCore

final class LogParserTests: XCTestCase {
    private let us = "\u{1f}", rs = "\u{1e}"

    func testParseLog() {
        let text = ["aaa111\(us)bbb222\(us)Efe Hascan\(us)e@x.com\(us)1700000000\(us)HEAD -> main, origin/main, tag: v1.0\(us)İlk: başlık | boru\(rs)",
                    "\nbbb222\(us)\(us)Ali\(us)a@x.com\(us)1690000000\(us)\(us)kök commit\(rs)",
                    "\nccc333\(us)aaa111 bbb222\(us)Ali\(us)a@x.com\(us)1690000001\(us)\(us)Merge branch 'x'\(rs)\n"].joined()
        let log = LogParser.parseLog(text)
        XCTAssertEqual(log.count, 3)
        XCTAssertEqual(log[0], CommitInfo(sha: "aaa111", parents: ["bbb222"], author: "Efe Hascan", email: "e@x.com",
                                          date: Date(timeIntervalSince1970: 1_700_000_000),
                                          refs: ["HEAD -> main", "origin/main", "tag: v1.0"], subject: "İlk: başlık | boru"))
        XCTAssertEqual(log[1].parents, [])
        XCTAssertEqual(log[1].refs, [])
        XCTAssertEqual(log[2].parents, ["aaa111", "bbb222"])
        XCTAssertTrue(log[2].isMerge)
    }

    func testParseLogSkipsBrokenRecords() {
        XCTAssertEqual(LogParser.parseLog(""), [])
        XCTAssertEqual(LogParser.parseLog("eksik\(us)alan\(rs)"), [])
        XCTAssertEqual(LogParser.parseLog("a\(us)\(us)x\(us)y\(us)zaman-değil\(us)\(us)s\(rs)").count, 0)
    }

    func testParseBranches() {
        let text = [
            "refs/heads/main\(us)aaa\(us)origin/main\(us)ahead 1, behind 2\(us)*\(us)1700000000",
            "refs/heads/feature/x\(us)bbb\(us)origin/feature/x\(us)gone\(us) \(us)1690000000",
            "refs/heads/yerel\(us)ccc\(us)\(us)\(us) \(us)1680000000",
            "refs/heads/sadece-geride\(us)ddd\(us)origin/s\(us)behind 4\(us) \(us)1680000001",
            "refs/remotes/origin/main\(us)aaa\(us)\(us)\(us) \(us)1700000000",
            "refs/remotes/origin/HEAD\(us)aaa\(us)\(us)\(us) \(us)1700000000",
            "refs/tags/v1\(us)eee\(us)\(us)\(us) \(us)1",
            "",
        ].joined(separator: "\n")
        let b = LogParser.parseBranches(text)
        XCTAssertEqual(b, [
            BranchInfo(name: "main", isRemote: false, isHead: true, commit: "aaa", upstream: "origin/main", ahead: 1, behind: 2,
                       date: Date(timeIntervalSince1970: 1_700_000_000)),
            BranchInfo(name: "feature/x", isRemote: false, isHead: false, commit: "bbb", upstream: "origin/feature/x", upstreamGone: true,
                       date: Date(timeIntervalSince1970: 1_690_000_000)),
            BranchInfo(name: "yerel", isRemote: false, isHead: false, commit: "ccc", date: Date(timeIntervalSince1970: 1_680_000_000)),
            BranchInfo(name: "sadece-geride", isRemote: false, isHead: false, commit: "ddd", upstream: "origin/s", behind: 4,
                       date: Date(timeIntervalSince1970: 1_680_000_001)),
            BranchInfo(name: "origin/main", isRemote: true, isHead: false, commit: "aaa", date: Date(timeIntervalSince1970: 1_700_000_000)),
        ])
    }
}
