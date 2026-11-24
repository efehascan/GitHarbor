import AppKit
import HarborCore
import SwiftUI

@main
struct GitHarborApp: App {
    @State private var store = HarborStore(fileURL: Snapshot.workspaceURL ?? HarborStore.defaultFileURL)
    @State private var ui = UIState()

    init() {
        // Görsel test: ayarlar hangi sekmeyle açılsın.
        if let tab = value(of: "--settings-tab") { UserDefaults.standard.set(tab, forKey: "settingsTab") }
    }

    var body: some Scene {
        Window("Git Harbor Desktop", id: "main") {
            MainView(store: store)
                .environment(ui)
                .frame(minWidth: 860, minHeight: 520)
                .task {
                    await Snapshot.runAPISmokeIfRequested()
                    if value(of: "--appearance") == nil { AppTheme.current.apply() }   // kayıtlı tema
                    Snapshot.applyTestOptions(store: store)
                    if Snapshot.outputPath == nil {
                        store.onEvent = { [store] event in
                            let name: String
                            switch event {
                            case .pulled(let repo, _, _), .attention(let repo, _): name = repo
                            }
                            let id = store.workspace.repos.first { $0.name == name }?.id
                            Notifier.post(event, logo: id.flatMap { RepoLogos.shared.pngURL(for: $0) })
                        }
                    }
                    store.start()
                    Snapshot.runIfRequested(store: store)
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1320, height: 820)

        Settings {
            SettingsView(store: store)
        }

        MenuBarExtra {
            MenuBarView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Depo Ekle…") { AddRepository.present(store: store) }
                    .keyboardShortcut("o")
                Button("Depo Klonla…") { ui.sheet = .clone }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Button("Yeni Depo…") { ui.sheet = .create }
                    .keyboardShortcut("n")
                Button("Yeni Klasör") { store.edit { $0.createFolder(named: "Yeni klasör") } }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .toolbar) {
                Button("Komut Paleti") { ui.paletteOpen.toggle() }
                    .keyboardShortcut("k")
                Button("Yenile") { store.refreshAll() }
                    .keyboardShortcut("r")
                Button("Bütün Depoları Getir") { store.fetchAll() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Divider()
                ForEach(Array(RepoTab.allCases.enumerated()), id: \.offset) { i, tab in
                    Button(tab.rawValue) { ui.tab = tab }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
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

/// Komut satırında bir bayrağın değeri (görsel test seçenekleri için).
func value(of flag: String) -> String? {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
    return args[i + 1]
}
