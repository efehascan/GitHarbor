import Foundation

/// Görev: `git status --porcelain=v2 --branch -z --untracked-files=all` çıktısını `RepoStatus`'a çevir.
public enum StatusParser {
    public static func parse(_ data: Data) -> RepoStatus {
        // TODO(Qwen): gövdeyi doldur
        RepoStatus()
    }
}
