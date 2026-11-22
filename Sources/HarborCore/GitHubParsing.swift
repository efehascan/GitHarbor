import Foundation

/// Görev: GitHub uzak adresini çöz; kontrol listesini özetle; metindeki #123 referanslarını bul.
public enum GitHubParsing {
    /// "https://github.com/o/r(.git)", "git@github.com:o/r(.git)", "ssh://git@github.com/o/r(.git)" → (o, r).
    /// github.com dışındaki sunucular ve eksik yollar nil.
    public static func repoID(fromRemote url: String) -> GitHubRepoID? {
        // TODO(Qwen)
        nil
    }

    public static func summarize(_ runs: [CheckRun]) -> CheckSummary {
        // TODO(Qwen)
        .none
    }

    /// Metindeki "#123" referanslarının numaraları (sırayla, tekrarsız). Önünde harf/rakam olan (ör. "a#1") sayılmaz.
    public static func issueNumbers(in text: String) -> [Int] {
        // TODO(Qwen)
        []
    }
}
