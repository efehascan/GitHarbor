import HarborCore
import SwiftUI
import UniformTypeIdentifiers

/// Kenar çubuğu: klasörler (adlandırılabilir, sürükle-bırak) ve klasörsüz depolar.
struct SidebarView: View {
    @Bindable var store: HarborStore
    @State private var renaming: UUID?
    @State private var draft = ""
    @State private var filter = ""
    @State private var collapsed = Set<UUID>()

    var body: some View {
        List(selection: $store.selection) {
            ForEach(store.workspace.folders) { folder in
                Section(isExpanded: expandedBinding(folder.id)) {
                    ForEach(visible(folder.repoIDs), id: \.self) { id in row(id) }
                        .onMove { from, to in move(in: folder.id, ids: folder.repoIDs, from: from, to: to) }
                } header: {
                    folderHeader(folder)
                }
                .dropDestination(for: URL.self) { items, _ in drop(items, into: folder.id) }
            }
            Section(store.workspace.folders.isEmpty ? "Depolar" : "Klasörsüz") {
                ForEach(visible(store.workspace.ungrouped), id: \.self) { id in row(id) }
                    .onMove { from, to in move(in: nil, ids: store.workspace.ungrouped, from: from, to: to) }
            }
            .dropDestination(for: URL.self) { items, _ in drop(items, into: nil) }
        }
        .listStyle(.sidebar)
        .searchable(text: $filter, placement: .sidebar, prompt: "Depo ara")
        .overlay {
            if store.workspace.repos.isEmpty {
                Text("Henüz depo yok")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Satırlar

    @ViewBuilder
    private func row(_ id: UUID) -> some View {
        if let repo = store.workspace.repo(id) {
            RepoRow(repo: repo, status: store.statuses[id], error: store.errors[id], sync: store.sync[id],
                    renaming: renaming == id, draft: $draft, commit: { commitRename(repo: id) })
                .tag(id)
                .draggable(RepoLink.url(id))
                .contextMenu { repoMenu(repo) }
        }
    }

    private func folderHeader(_ folder: RepoFolder) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .foregroundStyle(Theme.accent.opacity(0.85))
                .font(.system(size: 11))
            if renaming == folder.id {
                TextField("Klasör adı", text: $draft)
                    .textFieldStyle(.plain)
                    .onSubmit { commitRename(folder: folder.id) }
                    .onExitCommand { renaming = nil }
            } else {
                Text(folder.name)
            }
            Spacer()
            let pending = folder.repoIDs.reduce(0) { $0 + (store.statuses[$1]?.behind ?? 0 > 0 ? 1 : 0) }
            if pending > 0 {
                Text("\(pending)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Theme.behind.opacity(0.2), in: Capsule())
                    .foregroundStyle(Theme.behind)
                    .help("\(pending) depoda çekilecek değişiklik var")
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button("Yeniden Adlandır") { draft = folder.name; renaming = folder.id }
            Button("Depo Ekle…") { AddRepository.present(store: store, into: folder.id) }
            Divider()
            Button("Klasörü Sil", role: .destructive) { store.edit { $0.deleteFolder(folder.id) } }
        }
    }

    @ViewBuilder
    private func repoMenu(_ repo: RepoEntry) -> some View {
        Button("Yeniden Adlandır") { draft = repo.name; renaming = repo.id }
        Menu("Klasöre Taşı") {
            ForEach(store.workspace.folders) { f in
                Button(f.name) { store.edit { $0.move(repo: repo.id, to: f.id) } }
            }
            Divider()
            Button("Klasörsüz") { store.edit { $0.move(repo: repo.id, to: nil) } }
            Button("Yeni Klasöre…") {
                store.edit { w in
                    let f = w.createFolder(named: repo.name)
                    w.move(repo: repo.id, to: f.id)
                }
            }
        }
        Divider()
        Button("\(Editors.preferredName)'da Aç") { Editors.open(repo.path) }
        Button("Finder'da Göster") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repo.path)]) }
        Button("Terminalde Aç") {
            NSWorkspace.shared.open([URL(fileURLWithPath: repo.path)],
                                    withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                    configuration: NSWorkspace.OpenConfiguration())
        }
        Button("Yolu Kopyala") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(repo.path, forType: .string)
        }
        Divider()
        Button("Listeden Çıkar", role: .destructive) { store.edit { $0.removeRepo(repo.id) } }
    }

    // MARK: - Yardımcılar

    private func visible(_ ids: [UUID]) -> [UUID] {
        let q = filter.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return ids }
        return ids.filter { store.workspace.repo($0)?.name.localizedCaseInsensitiveContains(q) == true }
    }

    private func expandedBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { !collapsed.contains(id) || !filter.isEmpty },
                set: { if $0 { collapsed.remove(id) } else { collapsed.insert(id) } })
    }

    /// Uygulama içinden sürüklenen depo taşınır; Finder'dan gelen klasörler depo olarak eklenir.
    private func drop(_ items: [URL], into folder: UUID?) {
        let ids = items.compactMap(RepoLink.id)
        if !ids.isEmpty { store.edit { w in for id in ids { w.move(repo: id, to: folder) } } }
        let files = items.filter(\.isFileURL)
        if !files.isEmpty { Task { await store.addRepositories(at: files, into: folder) } }
    }

    private func move(in folder: UUID?, ids: [UUID], from: IndexSet, to: Int) {
        let shown = visible(ids)
        guard let first = from.first, shown.indices.contains(first) else { return }
        let id = shown[first]
        // Listeden çıkarıldıktan sonraki konum: aşağı taşırken bir eksik.
        let target = to > first ? to - 1 : to
        store.edit { $0.move(repo: id, to: folder, at: target) }
    }

    private func commitRename(folder: UUID) {
        let name = draft
        renaming = nil
        store.edit { $0.renameFolder(folder, to: name) }
    }

    private func commitRename(repo: UUID) {
        let name = draft
        renaming = nil
        store.edit { $0.renameRepo(repo, to: name) }
    }
}

private struct RepoRow: View {
    let repo: RepoEntry
    let status: RepoStatus?
    let error: String?
    let sync: RepoSyncState?
    let renaming: Bool
    @Binding var draft: String
    let commit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: error == nil ? "shippingbox.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(error == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.orange))
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                if renaming {
                    TextField("Ad", text: $draft)
                        .textFieldStyle(.plain)
                        .onSubmit(commit)
                } else {
                    Text(repo.name)
                        .lineLimit(1)
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if sync?.running != nil {
                ProgressView().controlSize(.mini)
            } else if sync?.operation ?? .none != .none {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.color(.conflicted))
                    .font(.system(size: 10)).help("Birleştirme / rebase sürüyor")
            } else if sync?.attention != nil {
                Circle().fill(Theme.behind).frame(width: 6, height: 6).help(sync?.attention ?? "")
            }
            if let status {
                SyncBadge(ahead: status.ahead, behind: status.behind)
                if !status.changes.isEmpty {
                    Text("\(Set(status.changes.map(\.path)).count)")
                        .font(.system(size: 10, weight: .semibold).monospacedDigit())
                        .padding(.horizontal, 6).padding(.vertical, 1.5)
                        .background(.quaternary, in: Capsule())
                        .help("Değişen dosya")
                }
            }
        }
        .padding(.vertical, 2)
        .help(repo.path)
    }

    private var subtitle: String {
        if let error { return error }
        guard let status else { return "…" }
        return status.branch ?? "ayrık HEAD " + String((status.commit ?? "").prefix(7))
    }
}

/// Uygulama içi sürükleme yükü: `githarbor://repo/<UUID>`.
enum RepoLink {
    static func url(_ id: UUID) -> URL {
        URL(string: "githarbor://repo/" + id.uuidString) ?? URL(fileURLWithPath: "/")
    }

    static func id(_ url: URL) -> UUID? {
        guard url.scheme == "githarbor", url.host == "repo" else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }
}
