import Foundation

/// Fark satırının türü.
public enum DiffLineKind: String, Hashable, Sendable {
    case context, added, removed
    /// "\ No newline at end of file" işareti: bir önceki satıra aittir.
    case noNewline
}

public struct DiffLine: Hashable, Sendable {
    public var kind: DiffLineKind
    /// Baştaki işaret (" ", "+", "-", "\") olmadan satır metni.
    public var text: String
    /// Eski dosyadaki satır numarası (eklenen ve işaret satırında nil).
    public var oldNumber: Int?
    /// Yeni dosyadaki satır numarası (silinen ve işaret satırında nil).
    public var newNumber: Int?
    public init(kind: DiffLineKind, text: String, oldNumber: Int? = nil, newNumber: Int? = nil) {
        self.kind = kind
        self.text = text
        self.oldNumber = oldNumber
        self.newNumber = newNumber
    }
}

public struct DiffHunk: Hashable, Sendable {
    public var oldStart: Int
    public var oldCount: Int
    public var newStart: Int
    public var newCount: Int
    /// "@@ -1,3 +1,4 @@ func x()" satırındaki @@'den sonraki bölüm ("func x()"), yoksa "".
    public var section: String
    public var lines: [DiffLine]
    public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, section: String = "", lines: [DiffLine] = []) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.section = section
        self.lines = lines
    }
}

/// Tek dosyanın farkı (`git diff --no-color --no-ext-diff` çıktısında bir `diff --git` bloğu).
public struct FileDiff: Hashable, Sendable {
    public var oldPath: String?
    public var newPath: String?
    public var isBinary: Bool
    public var isNewFile: Bool
    public var isDeletedFile: Bool
    /// "diff --git" satırından ilk "@@" satırına kadar olan başlık satırları (yama üretirken aynen kullanılır).
    public var header: [String]
    public var hunks: [DiffHunk]
    public init(oldPath: String? = nil, newPath: String? = nil, isBinary: Bool = false, isNewFile: Bool = false,
                isDeletedFile: Bool = false, header: [String] = [], hunks: [DiffHunk] = []) {
        self.oldPath = oldPath
        self.newPath = newPath
        self.isBinary = isBinary
        self.isNewFile = isNewFile
        self.isDeletedFile = isDeletedFile
        self.header = header
        self.hunks = hunks
    }
}

/// Bir satırın konumu: (parça sırası, satır sırası).
public struct DiffLineRef: Hashable, Sendable, Comparable {
    public var hunk: Int
    public var line: Int
    public init(hunk: Int, line: Int) {
        self.hunk = hunk
        self.line = line
    }
    public static func < (a: DiffLineRef, b: DiffLineRef) -> Bool {
        (a.hunk, a.line) < (b.hunk, b.line)
    }
}
