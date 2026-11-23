import XCTest
@testable import HarborCore

final class RepoHelpersTests: XCTestCase {
    func testCloneFolderName() {
        XCTAssertEqual(RepoHelpers.cloneFolderName("https://github.com/efehascan/PulseBar.git"), "PulseBar")
        XCTAssertEqual(RepoHelpers.cloneFolderName("https://github.com/efehascan/PulseBar"), "PulseBar")
        XCTAssertEqual(RepoHelpers.cloneFolderName("https://github.com/efehascan/PulseBar/"), "PulseBar")
        XCTAssertEqual(RepoHelpers.cloneFolderName("git@github.com:o/a-b.git"), "a-b")
        XCTAssertEqual(RepoHelpers.cloneFolderName("ssh://git@host:22/team/x.y.git"), "x.y")
        XCTAssertEqual(RepoHelpers.cloneFolderName("  /Users/me/remote.git  "), "remote")
        XCTAssertNil(RepoHelpers.cloneFolderName(""))
        XCTAssertNil(RepoHelpers.cloneFolderName("https://github.com/"))
        XCTAssertNil(RepoHelpers.cloneFolderName(".git"))
    }

    func testAddIgnore() {
        XCTAssertEqual(RepoHelpers.addIgnore("*.log", to: ""), "*.log\n")
        XCTAssertEqual(RepoHelpers.addIgnore("*.log", to: "node_modules/"), "node_modules/\n*.log\n")
        XCTAssertEqual(RepoHelpers.addIgnore("*.log", to: "node_modules/\n"), "node_modules/\n*.log\n")
        XCTAssertEqual(RepoHelpers.addIgnore("  *.log ", to: "a\n*.log\n"), "a\n*.log\n", "zaten varsa değişmez")
        XCTAssertEqual(RepoHelpers.addIgnore("*.log", to: "a\n  *.log  \n"), "a\n  *.log  \n", "boşluklu satır da aynı sayılır")
        XCTAssertEqual(RepoHelpers.addIgnore("", to: "a\n"), "a\n", "boş desen eklenmez")
    }

    func testExtensionPattern() {
        XCTAssertEqual(RepoHelpers.extensionPattern(for: "src/a.log"), "*.log")
        XCTAssertEqual(RepoHelpers.extensionPattern(for: "Paket.tar.gz"), "*.gz")
        XCTAssertNil(RepoHelpers.extensionPattern(for: "Makefile"))
        XCTAssertNil(RepoHelpers.extensionPattern(for: ".env"))
        XCTAssertNil(RepoHelpers.extensionPattern(for: "dir/.gitignore"))
    }

    func testWithCoAuthors() {
        let ali = (name: "Ali Veli", email: "ali@x.com")
        XCTAssertEqual(RepoHelpers.withCoAuthors("Özet", []), "Özet")
        XCTAssertEqual(RepoHelpers.withCoAuthors("Özet", [ali]), "Özet\n\nCo-authored-by: Ali Veli <ali@x.com>")
        XCTAssertEqual(RepoHelpers.withCoAuthors("Özet\n\nGövde\n", [ali, (name: "Ayşe", email: "a@y.com")]),
                       "Özet\n\nGövde\n\nCo-authored-by: Ali Veli <ali@x.com>\nCo-authored-by: Ayşe <a@y.com>")
        XCTAssertEqual(RepoHelpers.withCoAuthors("Özet\n\nCo-authored-by: Ali Veli <ali@x.com>", [ali]),
                       "Özet\n\nCo-authored-by: Ali Veli <ali@x.com>", "aynı satır tekrar eklenmez")
        XCTAssertEqual(RepoHelpers.withCoAuthors("Özet", [(name: "", email: "e@x.com"), (name: "Ad", email: " ")]), "Özet")
    }
}
