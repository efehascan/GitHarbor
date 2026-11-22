import Foundation

/// Görev: çalışma alanı düzenlemeleri (depo ekle/çıkar, klasör oluştur/adlandır/sil, taşı).
/// Hepsi saf; `Workspace` kuralını korur: her depo ya tam bir klasörde ya da `ungrouped` içinde.
extension Workspace {
    /// Aynı yol (standart hâli) zaten varsa mevcut kaydı döndürür, yeni ekleme yapmaz.
    @discardableResult
    public mutating func addRepo(path: String, name: String? = nil) -> RepoEntry {
        let std = URL(fileURLWithPath: path).standardizedFileURL.path
        if let existing = repos.first(where: { $0.path == std }) {
            return existing
        }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved: String
        if let trimmed, !trimmed.isEmpty {
            resolved = trimmed
        } else {
            resolved = std.components(separatedBy: "/").last ?? ""
        }
        let entry = RepoEntry(path: std, name: resolved)
        repos.append(entry)
        ungrouped.append(entry.id)
        return entry
    }

    public mutating func removeRepo(_ id: UUID) {
        guard repos.contains(where: { $0.id == id }) else { return }
        repos.removeAll { $0.id == id }
        ungrouped.removeAll { $0 == id }
        for i in folders.indices {
            folders[i].repoIDs.removeAll { $0 == id }
        }
    }

    @discardableResult
    public mutating func createFolder(named name: String) -> RepoFolder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? "Yeni klasör" : trimmed
        let folder = RepoFolder(name: resolved)
        folders.append(folder)
        return folder
    }

    public mutating func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = trimmed
    }

    public mutating func renameRepo(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard let index = repos.firstIndex(where: { $0.id == id }) else { return }
        repos[index].name = trimmed
    }

    /// Klasör silinir; içindeki depolar sırası korunarak `ungrouped` sonuna eklenir.
    public mutating func deleteFolder(_ id: UUID) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let moved = folders[index].repoIDs
        folders.remove(at: index)
        ungrouped.append(contentsOf: moved)
    }

    /// Depoyu `folder` klasörüne (nil ise klasörsüz alana) `index` konumuna taşır.
    public mutating func move(repo id: UUID, to folder: UUID?, at index: Int? = nil) {
        guard let entry = repos.first(where: { $0.id == id }) else { return }
        if let folder = folder {
            guard folders.contains(where: { $0.id == folder }) else { return }
        }
        // Önce depoyu her yerden çıkar (çıkarırken ungrouped sırası korunur).
        ungrouped.removeAll { $0 == entry.id }
        for i in folders.indices {
            folders[i].repoIDs.removeAll { $0 == entry.id }
        }
        // Hedef listeye ekle.
        if let folder = folder {
            guard let i = folders.firstIndex(where: { $0.id == folder }) else { return }
            let count = folders[i].repoIDs.count
            let pos = index.map { min(max($0, 0), count) } ?? count
            folders[i].repoIDs.insert(entry.id, at: pos)
        } else {
            let count = ungrouped.count
            let pos = index.map { min(max($0, 0), count) } ?? count
            ungrouped.insert(entry.id, at: pos)
        }
    }

    public func repo(_ id: UUID) -> RepoEntry? {
        repos.first { $0.id == id }
    }

    /// Deponun bulunduğu klasör; klasörsüzse nil.
    public func folder(containing id: UUID) -> RepoFolder? {
        folders.first { $0.repoIDs.contains(id) }
    }
}
