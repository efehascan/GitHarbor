import AppKit
import HarborCore
import SwiftUI

/// Çalışma ağaçları (git worktree): listele, yenisini aç, Harbor'a ekle, kaldır.
struct WorktreeButton: View {
    let store: HarborStore
    let repo: RepoEntry
    let request: Int
    @State private var open = false
    @State private var trees: [Worktree] = []
    @State private var branch = ""
    @State private var path = ""
    @State private var pathEdited = false
    @State private var busy = false
    @State private var error: String?
    @State private var removing: Worktree?

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 5) {
                Image(systemName: "square.stack.3d.up").font(.system(size: 14, weight: .medium)).foregroundStyle(.secondary)
                if trees.count > 1 {
                    Text("\(trees.count - 1)").font(.system(size: 12, weight: .semibold).monospacedDigit())
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 12)
            .fixedSize()
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
        }
        .help("Çalışma ağaçları (worktree)")
        .buttonStyle(.plain)
        .task(id: repo.id) {
            await reload()
            if CommandLine.arguments.contains("--worktrees") { open = true }   // görsel test
        }
        .onChange(of: request) { open = true }
        .onChange(of: open) { if open { Task { await reload() } } }
        .popover(isPresented: $open, arrowEdge: .bottom) { panel }
        .alert("Çalışma ağacı kaldırılsın mı?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Kaldır", role: .destructive) { if let t = removing { Task { await remove(t) } } }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("\(abbreviate(removing?.path ?? "")) klasörü silinir; dal ve commit'leri kalır. Kaydedilmemiş değişiklik varsa git kaldırmaz.")
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Çalışma ağaçları").font(.headline)
            Text("Aynı depoda başka bir dalı ayrı klasörde aç; dal değiştirmeden iki dalda birden çalış.")
                .font(.caption).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                TextField("Dal (yoksa oluşturulur; origin/x de olur)", text: $branch)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: branch) {
                        if !pathEdited { path = branch.isEmpty ? "" : WorktreeParser.suggestedPath(repo: repo.path, branch: branch) }
                    }
                    .onSubmit { Task { await add() } }
                HStack {
                    Text(path.isEmpty ? "Klasör: deponun yanında" : abbreviate(path))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button("Değiştir…") {
                        let parent = URL(fileURLWithPath: repo.path).deletingLastPathComponent().path
                        if let p = chooseFolder("Çalışma ağacının klasörü (boş olmalı)", initial: parent) {
                            path = p
                            pathEdited = true
                        }
                    }
                    .controlSize(.small)
                    Button("Oluştur") { Task { await add() } }
                        .buttonStyle(.glassProminent)
                        .controlSize(.small)
                        .disabled(branch.trimmingCharacters(in: .whitespaces).isEmpty || path.isEmpty || busy)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            Divider()
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(trees) { row($0) }
                }
            }
            // Açılır pencerede ScrollView kendi yüksekliğini bilmez; satır sayısına göre verilir.
            .frame(height: min(CGFloat(trees.count) * 56, 280))
            if trees.contains(where: \.isPrunable) {
                Button("Silinmiş klasörlerin kayıtlarını temizle") { Task { await prune() } }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 440)
        .disabled(busy)
    }

    private func row(_ t: Worktree) -> some View {
        let entry = store.workspace.repos.first { samePath($0.path, t.path) }
        return HStack(spacing: 8) {
            Image(systemName: t.isMain ? "house" : (t.isPrunable ? "questionmark.folder" : "folder"))
                .foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text(t.branch ?? "ayrık HEAD (\(t.head.prefix(7)))").lineLimit(1)
                    if t.isMain { tag("ana") }
                    if t.isLocked { tag("kilitli") }
                    if t.isPrunable { tag("klasör yok") }
                }
                Text(abbreviate(t.path)).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if !t.isPrunable {
                if let entry {
                    if entry.id != repo.id {
                        Button("Git") { store.selection = entry.id; open = false }.controlSize(.small)
                    }
                } else {
                    Button("Harbor'a ekle") { Task { await addToHarbor(t.path) } }.controlSize(.small)
                }
            }
            Menu {
                Button("Finder'da göster") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: t.path)]) }
                    .disabled(t.isPrunable)
                Button("\(Editors.preferredName)'da aç") { Editors.open(t.path) }.disabled(t.isPrunable)
                if !t.isMain {
                    Divider()
                    Button("Kaldır…", role: .destructive) { removing = t }.disabled(t.isLocked || t.isPrunable)
                }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
                .fixedSize()
        }
        .padding(8)
        .background(.quaternary.opacity(samePath(t.path, repo.path) ? 0.9 : 0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tag(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(Capsule().stroke(.tertiary))
    }

    private func samePath(_ a: String, _ b: String) -> Bool {
        URL(fileURLWithPath: a).resolvingSymlinksInPath().path == URL(fileURLWithPath: b).resolvingSymlinksInPath().path
    }

    private func reload() async {
        trees = (try? await Git.worktrees(in: repo.path)) ?? []
    }

    private func perform(_ work: () async throws -> Void) async {
        busy = true
        error = nil
        defer { busy = false }
        do { try await work() } catch { self.error = "\(error)" }
        await reload()
    }

    private func add() async {
        let b = branch.trimmingCharacters(in: .whitespaces), p = path
        guard !b.isEmpty, !p.isEmpty else { return }
        await perform {
            try await Git.addWorktree(path: p, branch: b, in: repo.path)
            await addToHarbor(p)
            branch = ""
            path = ""
            pathEdited = false
        }
    }

    /// Depoyla aynı klasöre ekler.
    private func addToHarbor(_ p: String) async {
        let folder = store.workspace.folder(containing: repo.id)?.id
        _ = await store.addRepositories(at: [URL(fileURLWithPath: p)], into: folder)
    }

    private func remove(_ t: Worktree) async {
        await perform {
            try await Git.removeWorktree(path: t.path, in: repo.path)
            if let entry = store.workspace.repos.first(where: { samePath($0.path, t.path) }) {
                store.edit { $0.removeRepo(entry.id) }
            }
        }
    }

    private func prune() async {
        await perform { try await Git.pruneWorktrees(in: repo.path) }
    }
}
