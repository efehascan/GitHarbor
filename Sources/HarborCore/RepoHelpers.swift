import Foundation

/// Görev: depo yardımcıları (saf fonksiyonlar): klon klasör adı, .gitignore ekleme, ortak yazar satırları.
public enum RepoHelpers {
    /// Klon adresinden klasör adı: "https://github.com/o/Proje.git" → "Proje"; "git@github.com:o/a-b.git" → "a-b";
    /// sondaki "/" ve ".git" atılır; ad çıkarılamazsa nil.
    public static func cloneFolderName(_ url: String) -> String? {
        // TODO(Qwen)
        nil
    }

    /// `.gitignore` içeriğine desen ekler. Desen (kırpılmış) zaten bir satır olarak varsa içerik değişmez.
    /// İçerik boş değilse ve "\n" ile bitmiyorsa önce "\n" eklenir; sonuç her zaman "\n" ile biter.
    public static func addIgnore(_ pattern: String, to content: String) -> String {
        // TODO(Qwen)
        content
    }

    /// Dosya yolundan uzantı deseni: "src/a.log" → "*.log"; uzantısız ya da gizli dosya (".env") → nil.
    public static func extensionPattern(for path: String) -> String? {
        // TODO(Qwen)
        nil
    }

    /// Commit mesajına ortak yazar satırları ekler: gövdenin sonuna boş satırdan sonra
    /// "Co-authored-by: Ad <e-posta>" (her biri bir satır). Mesajda zaten aynı satır varsa tekrar eklenmez.
    /// Boş ad ya da e-postalı kişi atlanır. Kimse yoksa mesaj aynen döner.
    public static func withCoAuthors(_ message: String, _ people: [(name: String, email: String)]) -> String {
        // TODO(Qwen)
        message
    }
}
