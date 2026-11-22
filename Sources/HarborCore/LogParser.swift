import Foundation

/// Görev: `git log` ve `git for-each-ref` çıktılarını ayrıştır. Biçimler aşağıdaki sabitlerde.
public enum LogParser {
    /// Alan ayırıcı 0x1f, kayıt ayırıcı 0x1e: sha, ebeveynler, yazar, e-posta, unix zaman, referanslar, özet.
    public static let logFormat = "%H%x1f%P%x1f%an%x1f%ae%x1f%at%x1f%D%x1f%s%x1e"
    /// refname, sha, upstream (kısa), takip ("ahead 1, behind 2" / "gone" / ""), HEAD ("*" ya da " "), unix zaman. Satır başına bir dal.
    public static let branchFormat = "%(refname)%1f%(objectname)%1f%(upstream:short)%1f%(upstream:track,nobracket)%1f%(HEAD)%1f%(committerdate:unix)"

    private static let unitSep = Character("\u{1f}")
    private static let recordSep = Character("\u{1e}")

    public static func parseLog(_ text: String) -> [CommitInfo] {
        var result: [CommitInfo] = []
        for raw in text.split(separator: recordSep) {
            let record = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !record.isEmpty else { continue }
            let fields = record.split(separator: unitSep, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 7, let time = Int(fields[4]) else { continue }
            let parents = fields[1].isEmpty ? [] : fields[1].split(separator: " ").map(String.init)
            let refs = fields[5].isEmpty ? [] : fields[5].components(separatedBy: ", ")
            result.append(CommitInfo(
                sha: fields[0],
                parents: parents,
                author: fields[2],
                email: fields[3],
                date: Date(timeIntervalSince1970: TimeInterval(time)),
                refs: refs,
                subject: fields[6]))
        }
        return result
    }

    public static func parseBranches(_ text: String) -> [BranchInfo] {
        var result: [BranchInfo] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let fields = line.split(separator: unitSep, omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 6, let time = Int(fields[5]) else { continue }
            let refname = fields[0]
            let name: String
            var isRemote = false
            if refname.hasPrefix("refs/heads/") {
                name = String(refname.dropFirst("refs/heads/".count))
            } else if refname.hasPrefix("refs/remotes/") {
                isRemote = true
                let short = String(refname.dropFirst("refs/remotes/".count))
                if short.hasSuffix("/HEAD") { continue }
                name = short
            } else {
                continue
            }

            let upstream = fields[2]
            var ahead = 0, behind = 0, upstreamGone = false
            let track = fields[3]
            if track == "gone" {
                upstreamGone = true
            } else {
                for part in track.components(separatedBy: ", ") where !part.isEmpty {
                    if part.hasPrefix("ahead ") {
                        if let n = Int(part.dropFirst("ahead ".count)) { ahead = n }
                    } else if part.hasPrefix("behind ") {
                        if let n = Int(part.dropFirst("behind ".count)) { behind = n }
                    }
                }
            }

            result.append(BranchInfo(
                name: name,
                isRemote: isRemote,
                isHead: fields[4] == "*",
                commit: fields[1],
                upstream: upstream.isEmpty ? nil : upstream,
                ahead: ahead,
                behind: behind,
                upstreamGone: upstreamGone,
                date: Date(timeIntervalSince1970: TimeInterval(time))))
        }
        return result
    }
}
