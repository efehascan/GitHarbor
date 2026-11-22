import Foundation

/// Görev: GitHub uzak adresini çöz; kontrol listesini özetle; metindeki #123 referanslarını bul.
public enum GitHubParsing {
    /// "https://github.com/o/r(.git)", "git@github.com:o/r(.git)", "ssh://git@github.com/o/r(.git)" → (o, r).
    /// github.com dışındaki sunucular ve eksik yollar nil.
    private static let failingConclusions: Set<String> = [
        "failure", "timed_out", "cancelled", "action_required", "startup_failure", "stale",
    ]

    public static func repoID(fromRemote url: String) -> GitHubRepoID? {
        let s = url.trimmingCharacters(in: .whitespacesAndNewlines)

        let path: String
        if s.lowercased().hasPrefix("git@github.com:") {
            // scp biçimi: önekin sonrasının tamamı yol (owner/repo[.git]).
            path = String(s.dropFirst("git@github.com:".count))
        } else {
            guard let u = URL(string: s),
                  u.scheme == "https" || u.scheme == "http" || u.scheme == "ssh" else {
                return nil
            }
            guard (u.host ?? "").lowercased() == "github.com" else { return nil }
            path = u.path
        }

        let components = path.split(separator: "/").map(String.init)
        guard components.count == 2 else { return nil }
        let owner = components[0]
        var name = components[1]
        guard !owner.isEmpty, !name.isEmpty else { return nil }
        if name.hasSuffix(".git") {
            name = String(name.dropLast(4))
        }
        guard !owner.isEmpty, !name.isEmpty else { return nil }
        return GitHubRepoID(owner: owner, name: name)
    }

    public static func summarize(_ runs: [CheckRun]) -> CheckSummary {
        let total = runs.count
        if total == 0 { return .none }

        var failed = 0
        var completed = 0
        var incomplete = 0
        for run in runs {
            let isCompleted = run.status == "completed"
            if isCompleted {
                completed += 1
                if let c = run.conclusion, failingConclusions.contains(c) {
                    failed += 1
                }
            } else {
                incomplete += 1
            }
        }

        if failed > 0 {
            return .failure(failed: failed, total: total)
        }
        if incomplete > 0 {
            return .pending(done: completed, total: total)
        }
        return .success(total: total)
    }

    /// Metindeki "#123" referanslarının numaraları (sırayla, tekrarsız). Önünde harf/rakam olan (ör. "a#1") sayılmaz.
    public static func issueNumbers(in text: String) -> [Int] {
        let chars = Array(text)
        var result: [Int] = []
        var seen = Set<Int>()

        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "#" {
                // Önceki karakter harf/rakamsa atla.
                let prevIsWord = i > 0 && (chars[i - 1].isLetter || chars[i - 1].isNumber)
                if !prevIsWord {
                    var j = i + 1
                    var digits = ""
                    while j < chars.count && chars[j].isASCII && chars[j].isNumber {
                        digits.append(chars[j])
                        j += 1
                    }
                    if !digits.isEmpty {
                        // Rakamlardan sonra harf geliyorsa (ör. "#0x") sayma.
                        let nextIsLetter = j < chars.count && chars[j].isLetter
                        if !nextIsLetter, let n = Int(digits), !seen.contains(n) {
                            seen.insert(n)
                            result.append(n)
                        }
                    }
                }
            }
            i += 1
        }

        return result
    }
}
