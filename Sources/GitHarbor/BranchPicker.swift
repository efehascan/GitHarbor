import HarborCore
import SwiftUI

/// Dal düğmesi + açılır panel: ara, geç, yeni dal, birleştir, rebase, yeniden adlandır, sil.
struct BranchButton: View {
    let session: HistorySession
    let status: RepoStatus
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Pill(icon: "arrow.triangle.branch", title: status.branch ?? "ayrık HEAD",
                 detail: status.upstream ?? (status.branch == nil ? String((status.commit ?? "").prefix(7)) : "yayınlanmamış dal"))
        }
        .buttonStyle(.plain)
        .help("Dallar")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            BranchPanel(session: session, current: status.branch, dirty: !status.changes.filter { $0.kind != .untracked }.isEmpty) {
                open = false
            }
        }
        .task(id: open) { if open { await session.reload() } }
    }
}

private struct BranchPanel: View {
    let session: HistorySession
    let current: String?
    let dirty: Bool
    let close: () -> Void

    @State private var query = ""
    @State private var newName = ""
    @State private var creating = false
    @State private var renaming: BranchInfo?
    @State private var confirmDelete: BranchInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Dal ara", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button { creating.toggle(); newName = "" } label: { Label("Yeni dal", systemImage: "plus") }
            }
            if creating {
                HStack {
                    TextField("yeni-dal-adı", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(create)
                    Button("Oluştur", action: create)
                        .buttonStyle(.glassProminent)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Text("\(current ?? "HEAD") üzerinden oluşturulur ve ona geçilir.").font(.caption).foregroundStyle(.secondary)
            }
            if dirty {
                Label("Kaydedilmemiş değişiklikler var; dal değiştirirken git çakışma görürse işlemi reddeder.",
                      systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    section("Yerel", filter(session.localBranches))
                    let remote = filter(session.remoteOnlyBranches)
                    if !remote.isEmpty { section("Uzak", remote) }
                }
            }
            .frame(height: 330)
        }
        .padding(14)
        .frame(width: 400)
        .disabled(session.busy)
        .alert("Dalı yeniden adlandır", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("ad", text: $newName)
            Button("Kaydet") { if let b = renaming { let n = newName; Task { await session.rename(b, to: n) } } }
            Button("Vazgeç", role: .cancel) {}
        }
        .confirmationDialog("\"\(confirmDelete?.name ?? "")\" silinsin mi?",
                            isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button("Sil", role: .destructive) { if let b = confirmDelete { Task { await session.delete(b, force: false) } } }
            Button("Birleştirilmemiş olsa da sil", role: .destructive) {
                if let b = confirmDelete { Task { await session.delete(b, force: true) } }
            }
        } message: {
            Text("Yerel dal silinir; uzak dala dokunulmaz. Birleştirilmemiş commit'ler zorla silmede kaybolabilir.")
        }
    }

    private func filter(_ list: [BranchInfo]) -> [BranchInfo] {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? list : list.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    private func create() {
        let n = newName
        creating = false
        Task { await session.createBranch(n, from: nil); close() }
    }

    @ViewBuilder
    private func section(_ title: String, _ list: [BranchInfo]) -> some View {
        Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 6)
        ForEach(list) { branch in
            BranchRow(branch: branch) {
                guard !branch.isHead else { return }
                Task { await session.switchTo(branch); close() }
            }
            .contextMenu {
                if !branch.isHead {
                    Button("Bu Dala Geç") { Task { await session.switchTo(branch); close() } }
                    Divider()
                    Button("\(current ?? "HEAD") dalına birleştir (merge)") { Task { await session.merge(branch) } }
                    Button("\(current ?? "HEAD") dalını bunun üzerine taşı (rebase)") { Task { await session.rebase(onto: branch) } }
                }
                if !branch.isRemote {
                    Divider()
                    Button("Yeniden Adlandır…") { newName = branch.name; renaming = branch }
                    if !branch.isHead {
                        Button("Sil…", role: .destructive) { confirmDelete = branch }
                    }
                }
                Divider()
                Button("Adı Kopyala") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(branch.name, forType: .string)
                }
            }
        }
    }
}

private struct BranchRow: View {
    let branch: BranchInfo
    let tap: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: branch.isHead ? "checkmark" : (branch.isRemote ? "cloud" : "arrow.triangle.branch"))
                .font(.system(size: 11, weight: branch.isHead ? .bold : .regular))
                .foregroundStyle(branch.isHead ? Theme.accent : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 0) {
                Text(branch.name).fontWeight(branch.isHead ? .semibold : .regular).lineLimit(1)
                Text(branch.date, format: .relative(presentation: .named))
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer()
            if branch.upstreamGone {
                Text("uzakta silinmiş").font(.system(size: 9.5)).foregroundStyle(.orange)
            }
            SyncBadge(ahead: branch.ahead, behind: branch.behind)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(hovering ? Color.secondary.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: tap)
    }
}
