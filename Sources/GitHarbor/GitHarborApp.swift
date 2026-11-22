import AppKit
import HarborCore
import SwiftUI

@main
struct GitHarborApp: App {
    @State private var store = HarborStore(fileURL: Snapshot.workspaceURL ?? HarborStore.defaultFileURL)

    var body: some Scene {
        Window("Git Harbor Desktop", id: "main") {
            MainView(store: store)
                .frame(minWidth: 860, minHeight: 520)
                .task {
                    store.start()
                    Snapshot.runIfRequested(store: store)
                }
        }
        .windowToolbarStyle(.unified)

        Settings {
            SettingsView(store: store)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Depo Ekle…") { AddRepository.present(store: store) }
                    .keyboardShortcut("o")
                Button("Yeni Klasör") { store.edit { $0.createFolder(named: "Yeni klasör") } }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Yenile") { store.refreshAll() }
                    .keyboardShortcut("r")
            }
        }
    }
}

enum AddRepository {
    @MainActor
    static func present(store: HarborStore, into folder: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Ekle"
        panel.message = "Bir depo ya da depoları içeren bir klasör seç"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls
        Task { await store.addRepositories(at: urls, into: folder) }
    }
}
