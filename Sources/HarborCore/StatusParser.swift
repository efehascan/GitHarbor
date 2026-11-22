import Foundation

/// Görev: `git status --porcelain=v2 --branch -z --untracked-files=all` çıktısını `RepoStatus`'a çevir.
public enum StatusParser {
    public static func parse(_ data: Data) -> RepoStatus {
        var status = RepoStatus()
        let rawRecords = data.split(separator: 0, omittingEmptySubsequences: true)
        let records = rawRecords.map { String(decoding: $0, as: UTF8.self) }
        var i = 0
        while i < records.count {
            let record = records[i]
            i += 1
            if record.hasPrefix("# ") {
                parseHeader(record, &status)
                continue
            }
            if record.hasPrefix("! ") {
                continue
            }
            if record.hasPrefix("? ") {
                status.changes.append(FileChange(path: String(record.dropFirst(2)),
                                                kind: .untracked, staged: false))
                continue
            }
            switch record.first {
            case "1":
                let parts = record.split(separator: " ", maxSplits: 8,
                                         omittingEmptySubsequences: false)
                if parts.count != 9 { continue }
                appendChange(parts: parts, pathIndex: 8, oldPathIndex: nil,
                             oldRecord: nil, status: &status)
            case "2":
                let parts = record.split(separator: " ", maxSplits: 9,
                                         omittingEmptySubsequences: false)
                if parts.count != 10 { continue }
                let oldRecord = i < records.count ? records[i] : nil
                if oldRecord != nil { i += 1 }
                appendChange(parts: parts, pathIndex: 9, oldPathIndex: 9,
                             oldRecord: oldRecord, status: &status)
            case "u":
                let parts = record.split(separator: " ", maxSplits: 10,
                                         omittingEmptySubsequences: false)
                if parts.count != 11 { continue }
                status.changes.append(FileChange(path: String(parts[10]),
                                                kind: .conflicted, staged: false))
            default:
                continue
            }
        }
        return status
    }

    private static func parseHeader(_ record: String, _ status: inout RepoStatus) {
        // Kayıt "# <anahtar> <değer>" biçimindedir. Baştaki "#" ile ilk boşluk
        // atlanır; kalan metnin ilk boşluğundan önceki parça anahtar, sonrası değer.
        guard record.hasPrefix("# ") else { return }
        let parts = record.dropFirst(2).split(separator: " ", maxSplits: 1,
                                              omittingEmptySubsequences: false)
        guard parts.count == 2 else { return }
        let key = String(parts[0])                    // "branch.oid"
        let value = String(parts[1])
        if key == "branch.oid" {
            status.commit = (value == "(initial)") ? nil : value
        } else if key == "branch.head" {
            status.branch = (value == "(detached)") ? nil : value
        } else if key == "branch.upstream" {
            status.upstream = value
        } else if key == "branch.ab" {
            var ahead = 0
            var behind = 0
            for token in value.split(separator: " ") {
                if token.hasPrefix("+") {
                    ahead = Int(token.dropFirst()) ?? 0
                } else if token.hasPrefix("-") {
                    behind = Int(token.dropFirst()) ?? 0
                }
            }
            status.ahead = ahead
            status.behind = behind
        }
    }

    private static func kind(forChar c: Character) -> ChangeKind {
        switch c {
        case "M": return .modified
        case "A": return .added
        case "D": return .deleted
        case "R": return .renamed
        case "C": return .copied
        case "T": return .typeChanged
        default: return .modified
        }
    }

    private static func appendChange(parts: [Substring],
                                    pathIndex: Int, oldPathIndex: Int?,
                                    oldRecord: String?, status: inout RepoStatus) {
        // XY = parts[1] (2 karakter).
        let xy = String(parts[1])
        guard xy.count == 2 else { return }
        let chars = Array(xy)
        let x = chars[0]
        let y = chars[1]
        let isRename = x == "R" || x == "C" || y == "R" || y == "C"
        // Yan tarafa (X / Y) ait yol.
        let sidePath = oldPathIndex != nil ? String(parts[oldPathIndex!]) : String(parts[pathIndex])
        // X tarafı (sahnelenmiş).
        if x != "." {
            let xOld = (oldPathIndex != nil && isRename) ? oldRecord : nil
            status.changes.append(FileChange(path: sidePath, oldPath: xOld,
                                             kind: kind(forChar: x), staged: true))
        }
        // Y tarafı (çalışma klasörü).
        if y != "." {
            let yOld = (oldPathIndex != nil && isRename) ? oldRecord : nil
            status.changes.append(FileChange(path: sidePath, oldPath: yOld,
                                             kind: kind(forChar: y), staged: false))
        }
    }
}
