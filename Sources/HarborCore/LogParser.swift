import Foundation

/// Görev: `git log` ve `git for-each-ref` çıktılarını ayrıştır. Biçimler aşağıdaki sabitlerde.
public enum LogParser {
    /// Alan ayırıcı 0x1f, kayıt ayırıcı 0x1e: sha, ebeveynler, yazar, e-posta, unix zaman, referanslar, özet.
    public static let logFormat = "%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s%x1e"
    /// refname, sha, upstream (kısa), takip ("ahead 1, behind 2" / "gone" / ""), HEAD ("*" ya da " "), unix zaman. Satır başına bir dal.
    public static let branchFormat = "%(refname)%1f%(objectname)%1f%(upstream:short)%1f%(upstream:track,nobracket)%1f%(HEAD)%1f%(committerdate:unix)"

    public static func parseLog(_ text: String) -> [CommitInfo] {
        // TODO(Qwen)
        []
    }

    public static func parseBranches(_ text: String) -> [BranchInfo] {
        // TODO(Qwen)
        []
    }
}
