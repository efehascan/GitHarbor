import Foundation

/// Bir farkın seçili satırlarından `git apply` ile uygulanabilecek yama üretir.
///
/// - `.forward`: yama eski → yeni yönünde uygulanır (çalışma farkından seçileni sahneye eklemek:
///   `git apply --cached`). Seçilmeyen eklemeler atılır, seçilmeyen silmeler bağlam olur.
/// - `.reverse`: yama tersine uygulanır (sahnedekini çıkarmak: `git apply --cached --reverse`,
///   çalışma klasöründe geri almak: `git apply --reverse`). Taban yeni taraftır: seçilmeyen
///   eklemeler bağlam olur, seçilmeyen silmeler atılır.
///
/// Satır sayıları yeniden hesaplanır; `git apply` yine de `--recount` ile çağrılır.
public enum PatchBuilder {
    public enum Direction: Sendable { case forward, reverse }

    /// Seçimde değişiklik satırı yoksa nil.
    public static func patch(for file: FileDiff, selecting selection: Set<DiffLineRef>, direction: Direction) -> String? {
        guard !file.isBinary else { return nil }
        var out: [String] = []
        var delta = 0
        var emitted = false

        for (h, hunk) in file.hunks.enumerated() {
            let picked = hunk.lines.indices.contains { i in
                let k = hunk.lines[i].kind
                return (k == .added || k == .removed) && selection.contains(DiffLineRef(hunk: h, line: i))
            }
            guard picked else {
                // Atlanan parça: ileri yönde sonraki parçaların yeni başlangıcı değişmez çünkü
                // bu parçanın değişiklikleri uygulanmıyor. Ters yönde taban yeni taraf olduğundan aynı.
                continue
            }
            var body: [String] = []
            var oldCount = 0, newCount = 0
            var lastKept = false
            for (i, line) in hunk.lines.enumerated() {
                let selected = selection.contains(DiffLineRef(hunk: h, line: i))
                switch line.kind {
                case .context:
                    body.append(" " + line.text); oldCount += 1; newCount += 1; lastKept = true
                case .added:
                    if selected {
                        body.append("+" + line.text); newCount += 1; lastKept = true
                    } else if direction == .reverse {
                        body.append(" " + line.text); oldCount += 1; newCount += 1; lastKept = true
                    } else {
                        lastKept = false
                    }
                case .removed:
                    if selected {
                        body.append("-" + line.text); oldCount += 1; lastKept = true
                    } else if direction == .forward {
                        body.append(" " + line.text); oldCount += 1; newCount += 1; lastKept = true
                    } else {
                        lastKept = false
                    }
                case .noNewline:
                    if lastKept { body.append("\\" + line.text) }
                }
            }
            // Ters yönde taban yeni taraftır; başlangıç yeni taraf numarasına göre kurulur.
            let oldStart: Int
            let newStart: Int
            if direction == .forward {
                oldStart = hunk.oldStart
                newStart = max(0, hunk.oldStart + delta + (oldCount == 0 ? 1 : 0) - (newCount == 0 ? 1 : 0))
            } else {
                newStart = hunk.newStart
                oldStart = max(0, hunk.newStart + delta + (newCount == 0 ? 1 : 0) - (oldCount == 0 ? 1 : 0))
            }
            delta += direction == .forward ? newCount - oldCount : oldCount - newCount
            let header = "@@ -\(range(oldStart, oldCount)) +\(range(newStart, newCount)) @@"
            out.append(header + (hunk.section.isEmpty ? "" : " " + hunk.section))
            out.append(contentsOf: body)
            emitted = true
        }
        guard emitted else { return nil }
        return (patchHeader(file) + out).joined(separator: "\n") + "\n"
    }

    /// Dosyanın bütün değişiklik satırlarının konumları (parça seçimi için de kullanılır).
    public static func changeRefs(in file: FileDiff, hunk only: Int? = nil) -> Set<DiffLineRef> {
        var refs = Set<DiffLineRef>()
        for (h, hunk) in file.hunks.enumerated() where only == nil || only == h {
            for (i, line) in hunk.lines.enumerated() where line.kind == .added || line.kind == .removed {
                refs.insert(DiffLineRef(hunk: h, line: i))
            }
        }
        return refs
    }

    private static func range(_ start: Int, _ count: Int) -> String {
        count == 1 ? "\(start)" : "\(start),\(count)"
    }

    /// Yama başlığı: `diff --git`, dosya kipleri ve `---`/`+++` satırları. `index` ve benzerlik satırları atılır
    /// (kısmi yamada nesne kimlikleri artık doğru olmaz).
    private static func patchHeader(_ file: FileDiff) -> [String] {
        let old = file.oldPath ?? file.newPath ?? ""
        let new = file.newPath ?? file.oldPath ?? ""
        var lines = ["diff --git a/\(old) b/\(new)"]
        for line in file.header where line.hasPrefix("new file mode") || line.hasPrefix("deleted file mode")
            || line.hasPrefix("old mode") || line.hasPrefix("new mode") {
            lines.append(line)
        }
        lines.append(file.oldPath == nil ? "--- /dev/null" : "--- a/\(old)")
        lines.append(file.newPath == nil ? "+++ /dev/null" : "+++ b/\(new)")
        return lines
    }
}
