import Foundation

/// `git diff --no-color --no-ext-diff` çıktısını dosya dosya `FileDiff`'e çevirir (kurallar haritada).
public enum DiffParser {
    public static func parse(_ text: String) -> [FileDiff] {
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }

        var result: [FileDiff] = []
        var file: FileDiff?
        var hunk: DiffHunk?
        var oldLine = 0, newLine = 0

        func closeHunk() {
            if let h = hunk { file?.hunks.append(h) }
            hunk = nil
        }
        func closeFile() {
            closeHunk()
            if let f = file { result.append(f) }
            file = nil
        }

        for line in lines {
            if line.hasPrefix("diff --git ") {
                closeFile()
                file = FileDiff(header: [line])
                continue
            }
            guard file != nil else { continue }

            if line.hasPrefix("@@ -"), let parsed = parseHunkHeader(line) {
                closeHunk()
                hunk = parsed
                oldLine = parsed.oldStart
                newLine = parsed.newStart
                continue
            }

            if hunk != nil {
                let body = line.isEmpty ? "" : String(line.dropFirst())
                switch line.first {
                case "+":
                    hunk?.lines.append(DiffLine(kind: .added, text: body, newNumber: newLine)); newLine += 1
                case "-":
                    hunk?.lines.append(DiffLine(kind: .removed, text: body, oldNumber: oldLine)); oldLine += 1
                case "\\":
                    hunk?.lines.append(DiffLine(kind: .noNewline, text: body))
                default:
                    hunk?.lines.append(DiffLine(kind: .context, text: body, oldNumber: oldLine, newNumber: newLine))
                    oldLine += 1; newLine += 1
                }
                continue
            }

            // Başlık satırı
            file?.header.append(line)
            if line.hasPrefix("new file mode") { file?.isNewFile = true }
            else if line.hasPrefix("deleted file mode") { file?.isDeletedFile = true }
            else if line.hasPrefix("Binary files ") || line == "GIT binary patch" { file?.isBinary = true }
            else if line.hasPrefix("rename from ") { file?.oldPath = String(line.dropFirst("rename from ".count)) }
            else if line.hasPrefix("rename to ") { file?.newPath = String(line.dropFirst("rename to ".count)) }
            else if line.hasPrefix("--- ") { file?.oldPath = side(line, prefix: "a/") }
            else if line.hasPrefix("+++ ") { file?.newPath = side(line, prefix: "b/") }
        }
        closeFile()

        // İkili dosya / salt kip değişikliği: ---/+++ yok; yollar diff --git satırından.
        for i in result.indices {
            let hasFileLines = result[i].header.contains { $0.hasPrefix("--- ") || $0.hasPrefix("rename from ") }
            if !hasFileLines, let git = result[i].header.first { fillPaths(&result[i], fromGitLine: git) }
            if result[i].isNewFile { result[i].oldPath = nil }
            if result[i].isDeletedFile { result[i].newPath = nil }
        }
        return result
    }

    /// "--- a/x" → "x"; "--- /dev/null" → nil. Sonda sekme ile eklenmiş zaman damgası atılır.
    private static func side(_ line: String, prefix: String) -> String? {
        var value = String(line.dropFirst(4))
        if let tab = value.firstIndex(of: "\t") { value = String(value[..<tab]) }
        if value == "/dev/null" { return nil }
        return value.hasPrefix(prefix) ? String(value.dropFirst(prefix.count)) : value
    }

    /// "diff --git a/X b/Y": " b/" son geçtiği yerden bölünür.
    private static func fillPaths(_ file: inout FileDiff, fromGitLine line: String) {
        let rest = line.dropFirst("diff --git ".count)
        guard rest.hasPrefix("a/"), let split = rest.range(of: " b/", options: .backwards) else { return }
        file.oldPath = String(rest[rest.index(rest.startIndex, offsetBy: 2)..<split.lowerBound])
        file.newPath = String(rest[split.upperBound...])
    }

    /// "@@ -a[,b] +c[,d] @@[ bölüm]"
    private static func parseHunkHeader(_ line: String) -> DiffHunk? {
        let afterStart = line.dropFirst(3)
        guard let end = afterStart.range(of: " @@") else { return nil }
        let ranges = afterStart[..<end.lowerBound].split(separator: " ")
        guard ranges.count == 2, ranges[0].hasPrefix("-"), ranges[1].hasPrefix("+"),
              let old = numbers(ranges[0].dropFirst()), let new = numbers(ranges[1].dropFirst()) else { return nil }
        var section = String(afterStart[end.upperBound...])
        if section.hasPrefix(" ") { section.removeFirst() }
        return DiffHunk(oldStart: old.0, oldCount: old.1, newStart: new.0, newCount: new.1, section: section)
    }

    private static func numbers(_ s: Substring) -> (Int, Int)? {
        let parts = s.split(separator: ",")
        guard let start = parts.first.flatMap({ Int($0) }) else { return nil }
        guard let count = parts.count > 1 ? Int(parts[1]) : 1 else { return nil }
        return (start, count)
    }
}
