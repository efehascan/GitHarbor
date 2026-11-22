import HarborCore
import SwiftUI

struct MainView: View {
    @Bindable var store: HarborStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 380)
        } detail: {
            if let id = store.selection, let repo = store.workspace.repo(id) {
                RepoDetailView(repo: repo, status: store.statuses[id], error: store.errors[id]) { store.refresh(id) }
                    .id(id)
            } else {
                EmptyState(hasRepos: !store.workspace.repos.isEmpty) {
                    AddRepository.present(store: store)
                }
                .dropDestination(for: URL.self) { items, _ in
                    let files = items.filter(\.isFileURL)
                    Task { await store.addRepositories(at: files) }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.edit { $0.createFolder(named: "Yeni klasör") } } label: {
                    Label("Yeni Klasör", systemImage: "folder.badge.plus")
                }
                .help("Yeni klasör (⇧⌘N)")
                Button { AddRepository.present(store: store) } label: {
                    Label("Depo Ekle", systemImage: "plus")
                }
                .help("Depo ekle (⌘O)")
            }
        }
    }
}

private struct EmptyState: View {
    let hasRepos: Bool
    let add: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "sailboat")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.accent.gradient)
            Text(hasRepos ? "Bir depo seç" : "Limana hoş geldin")
                .font(.title2.weight(.semibold))
            Text(hasRepos ? "Soldan bir depo seçerek değişikliklerini gör."
                          : "Depo klasörlerini buraya sürükle ya da ekle; klasörlere ayır, hepsini tek yerden izle.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            if !hasRepos {
                Button("Depo Ekle…", action: add)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .padding(.top, 6)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
