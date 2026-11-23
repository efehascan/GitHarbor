import HarborCore
import SwiftUI

struct MainView: View {
    @Bindable var store: HarborStore
    @Environment(UIState.self) private var ui
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 380)
        } detail: {
            if let id = store.selection, let repo = store.workspace.repo(id) {
                RepoDetailView(store: store, repo: repo)
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
        .overlay(alignment: .top) {
            if ui.paletteOpen {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.12).ignoresSafeArea()
                        .onTapGesture { ui.paletteOpen = false }
                    CommandPalette(store: store, ui: ui)
                        .padding(.top, 90)
                }
            }
        }
        .task {
            if CommandLine.arguments.contains("--settings") { openSettings() }   // görsel test
        }
        .sheet(item: Binding(get: { ui.sheet }, set: { ui.sheet = $0 })) { sheet in
            switch sheet {
            case .clone: CloneSheet(store: store)
            case .create: CreateRepoSheet(store: store)
            case .publish(let id): PublishSheet(store: store, repoID: id)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { store.edit { $0.createFolder(named: "Yeni klasör") } } label: {
                    Label("Yeni Klasör", systemImage: "folder.badge.plus")
                }
                .help("Yeni klasör (⇧⌘N)")
                Menu {
                    Button("Var olan depoyu ekle…") { AddRepository.present(store: store) }
                    Button("Depo klonla…") { ui.sheet = .clone }
                    Button("Yeni depo…") { ui.sheet = .create }
                } label: {
                    Label("Depo", systemImage: "plus")
                }
                .help("Depo ekle, klonla ya da oluştur")
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
