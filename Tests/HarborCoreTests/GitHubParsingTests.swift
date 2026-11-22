import XCTest
@testable import HarborCore

final class GitHubParsingTests: XCTestCase {
    func testRepoIDFromRemote() {
        let expected = GitHubRepoID(owner: "efehascan", name: "PulseBar")
        for url in ["https://github.com/efehascan/PulseBar.git", "https://github.com/efehascan/PulseBar",
                    "https://github.com/efehascan/PulseBar/", "git@github.com:efehascan/PulseBar.git",
                    "ssh://git@github.com/efehascan/PulseBar.git", "https://user@github.com/efehascan/PulseBar.git",
                    "  https://github.com/efehascan/PulseBar.git\n"] {
            XCTAssertEqual(GitHubParsing.repoID(fromRemote: url), expected, url)
        }
        XCTAssertEqual(GitHubParsing.repoID(fromRemote: "https://github.com/a/b.c.git"), GitHubRepoID(owner: "a", name: "b.c"))
        XCTAssertNil(GitHubParsing.repoID(fromRemote: "https://gitlab.com/a/b.git"))
        XCTAssertNil(GitHubParsing.repoID(fromRemote: "https://github.com/a"))
        XCTAssertNil(GitHubParsing.repoID(fromRemote: "/Users/x/remote.git"))
        XCTAssertNil(GitHubParsing.repoID(fromRemote: ""))
    }

    func testSummarize() {
        func run(_ status: String, _ conclusion: String?) -> CheckRun { CheckRun(id: 0, name: "x", status: status, conclusion: conclusion) }
        XCTAssertEqual(GitHubParsing.summarize([]), .none)
        XCTAssertEqual(GitHubParsing.summarize([run("completed", "success"), run("completed", "skipped"), run("completed", "neutral")]),
                       .success(total: 3))
        XCTAssertEqual(GitHubParsing.summarize([run("completed", "success"), run("in_progress", nil), run("queued", nil)]),
                       .pending(done: 1, total: 3))
        XCTAssertEqual(GitHubParsing.summarize([run("completed", "failure"), run("in_progress", nil), run("completed", "timed_out"),
                                                run("completed", "cancelled")]),
                       .failure(failed: 3, total: 4), "başarısızlık bekleyenden önce gelir")
        XCTAssertEqual(GitHubParsing.summarize([run("completed", "action_required")]), .failure(failed: 1, total: 1))
    }

    func testIssueNumbers() {
        XCTAssertEqual(GitHubParsing.issueNumbers(in: "Düzeltme #12, ayrıca #7 ve tekrar #12."), [12, 7])
        XCTAssertEqual(GitHubParsing.issueNumbers(in: "(#3) #4\n#5"), [3, 4, 5])
        XCTAssertEqual(GitHubParsing.issueNumbers(in: "renk #fff a#1 # 9 #0x"), [])
        XCTAssertEqual(GitHubParsing.issueNumbers(in: ""), [])
    }

    func testDecodePullRequest() throws {
        let json = """
        [{"number": 42, "title": "Yeni özellik", "body": null, "draft": true,
          "html_url": "https://github.com/o/r/pull/42", "updated_at": "2026-11-20T10:00:00Z",
          "user": {"login": "efe", "avatar_url": "https://x/a.png"},
          "head": {"ref": "ozellik", "sha": "abc", "repo": {"full_name": "fork/r"}},
          "base": {"ref": "main", "sha": "def", "repo": null}}]
        """
        let prs = try GitHubAPI.decoder.decode([PullRequest].self, from: Data(json.utf8))
        XCTAssertEqual(prs.count, 1)
        XCTAssertEqual(prs[0].number, 42)
        XCTAssertTrue(prs[0].draft)
        XCTAssertNil(prs[0].body)
        XCTAssertEqual(prs[0].head.repoFullName, "fork/r")
        XCTAssertNil(prs[0].base.repoFullName)
        XCTAssertEqual(prs[0].updatedAt, ISO8601DateFormatter().date(from: "2026-11-20T10:00:00Z"))
    }
}
