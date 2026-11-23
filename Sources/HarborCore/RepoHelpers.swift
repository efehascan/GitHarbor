import Foundation

/// Görev: depo yardımcıları (saf fonksiyonlar): klon klasör adı, .gitignore ekleme, ortak yazar satırları.
public enum RepoHelpers {
    /// Klon adresinden klasör adı: "https://github.com/o/Proje.git" → "Proje"; "git@github.com:o/a-b.git" → "a-b";
    /// sondaki "/" ve ".git" atılır; ad çıkarılamazsa nil.
    public static func cloneFolderName(_ url: String) -> String? {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        guard let sep = s.lastIndex(where: { $0 == "/" || $0 == ":" }) else {
            var name = s
            if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
            if name.isEmpty { return nil }
            return name
        }
        var name = String(s[s.index(after: sep)...])
        if name.hasSuffix(".git") { name = String(name.dropLast(4)) }
        if name.isEmpty { return nil }
        if let scheme = s.range(of: "://") {
            let after = s[scheme.upperBound...]
            if !after.contains("/") { return nil }
        }
        return name
    }

    /// `.gitignore` içeriğine desen ekler. Desen (kırpılmış) zaten bir satır olarak varsa içerik değişmez.
    /// İçerik boş değilse ve "\n" ile bitmiyorsa önce "\n" eklenir; sonuç her zaman "\n" ile biter.
    public static func addIgnore(_ pattern: String, to content: String) -> String {
        let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return content }
        let lines = content.components(separatedBy: "\n").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if lines.contains(p) { return content }
        var r = content
        if !r.isEmpty && !r.hasSuffix("\n") { r += "\n" }
        return r + p + "\n"
    }

    /// Dosya yolundan uzantı deseni: "src/a.log" → "*.log"; uzantısız ya da gizli dosya (".env") → nil.
    public static func extensionPattern(for path: String) -> String? {
        let name = (path as NSString).lastPathComponent
        if name.hasPrefix(".") { return nil }
        guard let dot = name.lastIndex(of: ".") else { return nil }
        let ext = String(name[name.index(after: dot)...])
        if ext.isEmpty { return nil }
        return "*." + ext
    }

    /// Commit mesajına ortak yazar satırları ekler: gövdenin sonuna boş satırdan sonra
    /// "Co-authored-by: Ad <e-posta>" (her biri bir satır). Mesajda zaten aynı satır varsa tekrar eklenmez.
    /// Boş ad ya da e-postalı kişi atlanır. Kimse yoksa mesaj aynen döner.
    public static func withCoAuthors(_ message: String, _ people: [(name: String, email: String)]) -> String {
        var lines: [String] = []
        for person in people {
            let name = person.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let email = person.email.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !email.isEmpty else { continue }
            let line = "Co-authored-by: \(name) <\(email)>"
            guard !message.contains(line) else { continue }
            lines.append(line)
        }
        if lines.isEmpty { return message }
        let base = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator: String = {
            guard let last = base.split(separator: "\n", omittingEmptySubsequences: false).last else {
                return "\n\n"
            }
            return last.hasPrefix("Co-authored-by:") ? "\n" : "\n\n"
        }()
        return base + separator + lines.joined(separator: "\n")
    }
}
