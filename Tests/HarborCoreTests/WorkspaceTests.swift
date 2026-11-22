import XCTest
@testable import HarborCore

final class WorkspaceTests: XCTestCase {
    /// Kural: her depo tam bir yerde (bir klasörde ya da ungrouped'ta).
    private func assertInvariant(_ w: Workspace, file: StaticString = #filePath, line: UInt = #line) {
        let placed = w.ungrouped + w.folders.flatMap(\.repoIDs)
        XCTAssertEqual(placed.count, Set(placed).count, "bir depo iki yerde", file: file, line: line)
        XCTAssertEqual(Set(placed), Set(w.repos.map(\.id)), "yerleşim depolarla uyuşmuyor", file: file, line: line)
    }

    func testAddRepoDefaultsNameAndDeduplicates() {
        var w = Workspace()
        let a = w.addRepo(path: "/Users/x/Code/PulseBar")
        XCTAssertEqual(a.name, "PulseBar")
        XCTAssertEqual(w.ungrouped, [a.id])
        let again = w.addRepo(path: "/Users/x/Code/PulseBar/")
        XCTAssertEqual(again.id, a.id)
        XCTAssertEqual(w.repos.count, 1)
        let b = w.addRepo(path: "/Users/x/Code/islet", name: "Islet")
        XCTAssertEqual(b.name, "Islet")
        XCTAssertEqual(w.ungrouped, [a.id, b.id])
        assertInvariant(w)
    }

    func testFoldersMoveAndDelete() {
        var w = Workspace()
        let a = w.addRepo(path: "/r/a"), b = w.addRepo(path: "/r/b"), c = w.addRepo(path: "/r/c")
        let work = w.createFolder(named: "İş")
        XCTAssertEqual(w.folders.map(\.name), ["İş"])
        w.move(repo: a.id, to: work.id)
        w.move(repo: c.id, to: work.id, at: 0)
        XCTAssertEqual(w.folders[0].repoIDs, [c.id, a.id])
        XCTAssertEqual(w.ungrouped, [b.id])
        XCTAssertEqual(w.folder(containing: a.id)?.id, work.id)
        XCTAssertNil(w.folder(containing: b.id))
        assertInvariant(w)

        // Aynı klasörde yeniden sıralama
        w.move(repo: a.id, to: work.id, at: 0)
        XCTAssertEqual(w.folders[0].repoIDs, [a.id, c.id])
        // Aşırı büyük index sona ekler
        w.move(repo: b.id, to: work.id, at: 99)
        XCTAssertEqual(w.folders[0].repoIDs, [a.id, c.id, b.id])
        XCTAssertEqual(w.ungrouped, [])
        assertInvariant(w)

        w.move(repo: c.id, to: nil)
        XCTAssertEqual(w.ungrouped, [c.id])
        w.deleteFolder(work.id)
        XCTAssertEqual(w.folders, [])
        XCTAssertEqual(w.ungrouped, [c.id, a.id, b.id])
        assertInvariant(w)
    }

    func testRenameAndRemove() {
        var w = Workspace()
        let a = w.addRepo(path: "/r/a")
        let f = w.createFolder(named: "Kişisel")
        w.move(repo: a.id, to: f.id)
        w.renameFolder(f.id, to: "  Yan projeler  ")
        XCTAssertEqual(w.folders[0].name, "Yan projeler")
        w.renameFolder(f.id, to: "   ")
        XCTAssertEqual(w.folders[0].name, "Yan projeler", "boş ad yok sayılır")
        w.renameRepo(a.id, to: "Alfa")
        XCTAssertEqual(w.repo(a.id)?.name, "Alfa")
        w.removeRepo(a.id)
        XCTAssertNil(w.repo(a.id))
        XCTAssertEqual(w.folders[0].repoIDs, [])
        assertInvariant(w)
    }

    func testUnknownIDsAreIgnored() {
        var w = Workspace()
        let a = w.addRepo(path: "/r/a")
        let before = w
        w.move(repo: UUID(), to: nil)
        w.move(repo: a.id, to: UUID())
        w.removeRepo(UUID())
        w.deleteFolder(UUID())
        w.renameFolder(UUID(), to: "x")
        XCTAssertEqual(w, before)
    }

    func testCodableRoundTrip() throws {
        var w = Workspace()
        let a = w.addRepo(path: "/r/a")
        let f = w.createFolder(named: "F")
        w.move(repo: a.id, to: f.id)
        let back = try JSONDecoder().decode(Workspace.self, from: JSONEncoder().encode(w))
        XCTAssertEqual(back, w)
    }
}
