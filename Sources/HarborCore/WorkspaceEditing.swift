import Foundation

/// Görev: çalışma alanı düzenlemeleri (depo ekle/çıkar, klasör oluştur/adlandır/sil, taşı).
/// Hepsi saf; `Workspace` kuralını korur: her depo ya tam bir klasörde ya da `ungrouped` içinde.
extension Workspace {
    /// Aynı yol (standart hâli) zaten varsa mevcut kaydı döndürür, yeni ekleme yapmaz.
    @discardableResult
    public mutating func addRepo(path: String, name: String? = nil) -> RepoEntry {
        // TODO(Qwen)
        RepoEntry(path: path, name: name ?? "")
    }

    public mutating func removeRepo(_ id: UUID) {
        // TODO(Qwen)
    }

    @discardableResult
    public mutating func createFolder(named name: String) -> RepoFolder {
        // TODO(Qwen)
        RepoFolder(name: name)
    }

    public mutating func renameFolder(_ id: UUID, to name: String) {
        // TODO(Qwen)
    }

    public mutating func renameRepo(_ id: UUID, to name: String) {
        // TODO(Qwen)
    }

    /// Klasör silinir; içindeki depolar sırası korunarak `ungrouped` sonuna eklenir.
    public mutating func deleteFolder(_ id: UUID) {
        // TODO(Qwen)
    }

    /// Depoyu `folder` klasörüne (nil ise klasörsüz alana) `index` konumuna taşır.
    public mutating func move(repo id: UUID, to folder: UUID?, at index: Int? = nil) {
        // TODO(Qwen)
    }

    public func repo(_ id: UUID) -> RepoEntry? {
        // TODO(Qwen)
        nil
    }

    /// Deponun bulunduğu klasör; klasörsüzse nil.
    public func folder(containing id: UUID) -> RepoFolder? {
        // TODO(Qwen)
        nil
    }
}
