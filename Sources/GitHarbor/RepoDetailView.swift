import HarborCore
import SwiftUI

/// Seçili deponun ekranı: başlık (dal, senkron, stash), solda değişiklikler ve commit kutusu, sağda fark.
struct RepoDetailView: View {
    let store: HarborStore
    let repo: RepoEntry
    @State private var session: ChangesSession

    init(store: HarborStore, repo: RepoEntry) {
        self.store = store
        self.repo = repo
        let id = repo.id
        _session = State(initialValue: ChangesSession(repo: repo, onChange: { [weak store] in
            Task { await store?.refreshOperation(id) }
        }))
    }

    private var status: RepoStatus? { store.statuses[repo.id] }
    private var error: String? { store.errors[repo.id] }
    private var operation: RepoOperation { store.sync[repo.id]?.operation ?? .none }

    var body: some View {
        VStack(spacing: 0) {
            header
            SyncBanner(store: store, id: repo.id)
            Divider()
            if let error {
                message("exclamationmark.triangle", error)
            } else if status != nil {
                HSplitView {
                    ChangesPane(session: session)
                        .frame(minWidth: 280, idealWidth: 330, maxWidth: 460)
                    DiffPane(session: session)
                        .frame(minWidth: 380, maxWidth: .infinity)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(repo.name)
        .navigationSubtitle(status?.branch ?? "")
        .task(id: status) { if let status { session.update(status: status, operation: operation) } }
        .task(id: operation) { if let status { session.update(status: status, operation: operation) } }
        .task {
            await session.loadStashes()
            await store.refreshOperation(repo.id)
        }
        .alert("İşlem yapılamadı", isPresented: Binding(get: { session.lastError != nil }, set: { if !$0 { session.lastError = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(session.lastError ?? "")
        }
        .alert("Senkron yapılamadı", isPresented: Binding(get: { store.syncAlert != nil }, set: { if !$0 { store.syncAlert = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: {
            Text(store.syncAlert ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name).font(.title2.weight(.semibold))
                Text(abbreviated(repo.path))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if let status {
                Pill(icon: "arrow.triangle.branch", title: status.branch ?? "ayrık HEAD",
                     detail: status.upstream ?? "yayınlanmamış dal")
                StashButton(session: session)
                SyncButton(store: store, id: repo.id, status: status)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 14)
    }

    private func message(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

struct Pill: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint ?? .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }
}

/// Stash: değişiklikleri sakla, listedekileri geri getir ya da sil.
private struct StashButton: View {
    let session: ChangesSession
    @State private var open = false
    @State private var note = ""

    var body: some View {
        Button { open.toggle() } label: {
            Pill(icon: "tray.full", title: "\(session.stashes.count) saklı", detail: "stash")
        }
        .buttonStyle(.plain)
        .popover(isPresented: $open, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saklanan değişiklikler").font(.headline)
                HStack {
                    TextField("Not (isteğe bağlı)", text: $note)
                        .textFieldStyle(.roundedBorder)
                    Button("Sakla") {
                        let n = note
                        note = ""
                        Task { await session.stash(message: n) }
                    }
                    .disabled(session.status.isClean || session.busy)
                }
                Text("Bütün değişiklikler (izlenmeyen dosyalar dahil) saklanır, çalışma klasörü temizlenir.")
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                if session.stashes.isEmpty {
                    Text("Saklı değişiklik yok").foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(session.stashes) { entry in
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(entry.message).lineLimit(1)
                                        Text("\(entry.ref) · \(entry.relativeDate)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Geri getir") { Task { await session.restore(entry, pop: true) } }
                                        .help("Değişiklikleri geri getirir ve saklananı siler (pop)")
                                    Menu {
                                        Button("Uygula, saklı kalsın") { Task { await session.restore(entry, pop: false) } }
                                        Divider()
                                        Button("Sil", role: .destructive) { Task { await session.drop(entry) } }
                                    } label: { Image(systemName: "ellipsis") }
                                        .menuStyle(.borderlessButton)
                                        .fixedSize()
                                }
                                .padding(8)
                                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                    .frame(maxHeight: 260)
                }
            }
            .padding(16)
            .frame(width: 380)
            .disabled(session.busy)
        }
    }
}
