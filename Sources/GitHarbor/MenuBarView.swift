import HarborCore
import SwiftUI

/// Menü çubuğu: çekilecek / gönderilecek değişikliği olan depolar; tıklayınca pencerede açar.
struct MenuBarView: View {
    let store: HarborStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let pending = store.workspace.repos.compactMap { repo -> (RepoEntry, RepoStatus)? in
            guard let s = store.statuses[repo.id], s.ahead > 0 || s.behind > 0 || !s.changes.isEmpty else { return nil }
            return (repo, s)
        }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Git Harbor").font(.headline)
                Spacer()
                Button { store.fetchAll() } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                    .buttonStyle(.borderless)
                    .help("Bütün depoları getir")
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            Divider()
            if pending.isEmpty {
                Label("Her şey güncel", systemImage: "checkmark.seal")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 22)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(pending, id: \.0.id) { repo, status in
                            Button { open(repo.id) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "shippingbox.fill").foregroundStyle(.secondary).font(.system(size: 11))
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(repo.name).lineLimit(1)
                                        Text(status.branch ?? "ayrık HEAD").font(.system(size: 10.5)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if store.sync[repo.id]?.running != nil { ProgressView().controlSize(.mini) }
                                    SyncBadge(ahead: status.ahead, behind: status.behind)
                                    if !status.changes.isEmpty {
                                        Text("\(Set(status.changes.map(\.path)).count)")
                                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                                            .padding(.horizontal, 5).padding(.vertical, 1)
                                            .background(.quaternary, in: Capsule())
                                    }
                                }
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(4)
                }
                .frame(maxHeight: 360)
            }
            Divider()
            HStack {
                Button("Pencereyi aç") { open(nil) }
                Spacer()
                Button("Çık") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .frame(width: 320)
    }

    private func open(_ id: UUID?) {
        if let id { store.selection = id }
        openWindow(id: "main")
        NSApp.activate()
    }
}

/// Menü çubuğu simgesi: gelen değişikliği olan depo sayısı.
struct MenuBarLabel: View {
    let store: HarborStore
    var body: some View {
        let behind = store.workspace.repos.filter { (store.statuses[$0.id]?.behind ?? 0) > 0 }.count
        HStack(spacing: 2) {
            Image(systemName: "sailboat.fill")
            if behind > 0 { Text("\(behind)").monospacedDigit() }
        }
    }
}
