import XCTest
@testable import HarborCore

final class DiffParserTests: XCTestCase {
    func testModifiedFileWithTwoHunks() {
        let text = """
        diff --git a/src/app.swift b/src/app.swift
        index 1111111..2222222 100644
        --- a/src/app.swift
        +++ b/src/app.swift
        @@ -1,3 +1,4 @@ import Foundation
         let a = 1
        -let b = 2
        +let b = 3
        +let c = 4
         let d = 5
        @@ -10,2 +11,2 @@
         x
        -y
        +z

        """
        let files = DiffParser.parse(text)
        XCTAssertEqual(files.count, 1)
        let f = files[0]
        XCTAssertEqual(f.oldPath, "src/app.swift")
        XCTAssertEqual(f.newPath, "src/app.swift")
        XCTAssertFalse(f.isBinary || f.isNewFile || f.isDeletedFile)
        XCTAssertEqual(f.header, ["diff --git a/src/app.swift b/src/app.swift", "index 1111111..2222222 100644",
                                  "--- a/src/app.swift", "+++ b/src/app.swift"])
        XCTAssertEqual(f.hunks.count, 2)
        let h = f.hunks[0]
        XCTAssertEqual([h.oldStart, h.oldCount, h.newStart, h.newCount], [1, 3, 1, 4])
        XCTAssertEqual(h.section, "import Foundation")
        XCTAssertEqual(h.lines, [
            DiffLine(kind: .context, text: "let a = 1", oldNumber: 1, newNumber: 1),
            DiffLine(kind: .removed, text: "let b = 2", oldNumber: 2, newNumber: nil),
            DiffLine(kind: .added, text: "let b = 3", oldNumber: nil, newNumber: 2),
            DiffLine(kind: .added, text: "let c = 4", oldNumber: nil, newNumber: 3),
            DiffLine(kind: .context, text: "let d = 5", oldNumber: 3, newNumber: 4),
        ])
        XCTAssertEqual(f.hunks[1].section, "")
        XCTAssertEqual(f.hunks[1].lines.map(\.newNumber), [11, nil, 12])
    }

    func testNewDeletedAndSingleLineCounts() {
        let text = """
        diff --git a/new.txt b/new.txt
        new file mode 100644
        index 0000000..e69de29
        --- /dev/null
        +++ b/new.txt
        @@ -0,0 +1 @@
        +merhaba
        diff --git a/old.txt b/old.txt
        deleted file mode 100644
        index e69de29..0000000
        --- a/old.txt
        +++ /dev/null
        @@ -1 +0,0 @@
        -güle güle
        """
        let files = DiffParser.parse(text)
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files[0].isNewFile)
        XCTAssertNil(files[0].oldPath)
        XCTAssertEqual(files[0].newPath, "new.txt")
        XCTAssertEqual([files[0].hunks[0].oldStart, files[0].hunks[0].oldCount, files[0].hunks[0].newStart, files[0].hunks[0].newCount], [0, 0, 1, 1])
        XCTAssertTrue(files[1].isDeletedFile)
        XCTAssertEqual(files[1].oldPath, "old.txt")
        XCTAssertNil(files[1].newPath)
        XCTAssertEqual(files[1].hunks[0].lines, [DiffLine(kind: .removed, text: "güle güle", oldNumber: 1, newNumber: nil)])
    }

    func testRenameBinaryAndNoNewline() {
        let text = """
        diff --git a/a b.txt b/c d.txt
        similarity index 90%
        rename from a b.txt
        rename to c d.txt
        index 1..2 100644
        --- a/a b.txt
        +++ b/c d.txt
        @@ -1 +1 @@
        -eski
        \\ No newline at end of file
        +yeni
        \\ No newline at end of file
        diff --git a/logo.png b/logo.png
        index 3..4 100644
        Binary files a/logo.png and b/logo.png differ
        """
        let files = DiffParser.parse(text)
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(files[0].oldPath, "a b.txt")
        XCTAssertEqual(files[0].newPath, "c d.txt")
        XCTAssertEqual(files[0].hunks[0].lines.map(\.kind), [.removed, .noNewline, .added, .noNewline])
        XCTAssertEqual(files[0].hunks[0].lines[1], DiffLine(kind: .noNewline, text: " No newline at end of file"))
        XCTAssertTrue(files[1].isBinary)
        XCTAssertEqual(files[1].newPath, "logo.png")
        XCTAssertEqual(files[1].hunks, [])
        XCTAssertEqual(files[1].header.last, "Binary files a/logo.png and b/logo.png differ")
    }

    func testEmptyAndContentStartingWithDashes() {
        XCTAssertEqual(DiffParser.parse(""), [])
        let text = """
        diff --git a/m.md b/m.md
        index 1..2 100644
        --- a/m.md
        +++ b/m.md
        @@ -1,2 +1,2 @@
        ---- başlık
        +++ artı
         son
        """
        let lines = DiffParser.parse(text)[0].hunks[0].lines
        XCTAssertEqual(lines.map(\.kind), [.removed, .added, .context])
        XCTAssertEqual(lines.map(\.text), ["--- başlık", "++ artı", "son"])
    }
}
