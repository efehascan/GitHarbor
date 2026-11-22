import HarborCore
import SwiftUI

/// Arayüz durumu: seçili sekme ve palet. Ortamdan (environment) okunur.
@MainActor
@Observable
final class UIState {
    var tab: RepoTab = CommandLine.arguments.contains("--history") ? .history
        : CommandLine.arguments.contains("--pulls") ? .pulls : .changes
    var paletteOpen = CommandLine.arguments.contains("--palette")
    /// Palet ya da menüden gelen "yeni dal" isteği (dal panelini açar).
    var branchPanelRequest = 0
    var stashRequest = 0
}

enum RepoTab: String, CaseIterable {
    case changes = "Değişiklikler", history = "Geçmiş", pulls = "Pull Request"
}

/// ⌘K: depoya git, işlemleri çalıştır, sekme değiştir.
struct CommandPalette: View {
    let store: HarborStore
    @Bindable var ui: UIState
    @State private var query = CommandLine.arguments.contains("--palette") ? "çek" : ""
    @State private var index = 0
    @FocusState private var focused: Bool

    struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let run: @MainActor () -> Void
    }

    var body: some View {
        let results = FuzzyMatch.rank(query, items, key: { $0.title })
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Depo ya da komut ara", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .focused($focused)
                    .onSubmit { run(results) }
                    .onKeyPress(.downArrow) { index = min(index + 1, max(results.count - 1, 0)); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }
                    .onChange(of: query) { index = 0 }
                Text("esc").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.tertiary))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(results.prefix(40).enumerated()), id: \.element.id) { i, item in
                            row(item, selected: i == index)
                                .id(i)
                                .onTapGesture { index = i; run(results) }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: index) { proxy.scrollTo(index) }
            }
            .frame(height: 340)
            .overlay { if results.isEmpty { Text("Sonuç yok").foregroundStyle(.secondary) } }
        }
        .frame(width: 560)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
        .onAppear { focused = true }
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 11) {
            Image(systemName: item.icon)
                .frame(width: 22)
                .foregroundStyle(selected ? Color.white : Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1)
                if !item.subtitle.isEmpty {
                    Text(item.subtitle).font(.system(size: 11)).lineLimit(1)
                        .foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary)
                }
            }
            Spacer()
            if selected { Image(systemName: "return").font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)) }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(selected ? Theme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }

    private func run(_ results: [Item]) {
        guard results.indices.contains(index) else { return }
        let item = results[index]
        close()
        item.run()
    }

    private func close() {
        ui.paletteOpen = false
        query = ""
    }

    private var items: [Item] {
        var list: [Item] = []
        let selected = store.selection
        if let id = selected, let repo = store.workspace.repo(id) {
            let s = store.statuses[id]
            list += [
                Item(id: "fetch", title: "Getir (fetch)", subtitle: repo.name, icon: "arrow.triangle.2.circlepath") {
                    Task { await store.fetch(id) }
                },
                Item(id: "pull", title: "Çek (pull)", subtitle: s.map { "\(repo.name) · \($0.behind) gelen" } ?? repo.name,
                     icon: "arrow.down.circle") { Task { await store.pull(id, mode: .merge) } },
                Item(id: "push", title: s?.upstream == nil ? "Dalı yayınla" : "Gönder (push)",
                     subtitle: s.map { "\(repo.name) · \($0.ahead) giden" } ?? repo.name, icon: "arrow.up.circle") {
                    Task { await store.push(id) }
                },
                Item(id: "branch", title: "Yeni dal…", subtitle: repo.name, icon: "arrow.triangle.branch") {
                    ui.branchPanelRequest += 1
                },
                Item(id: "stash", title: "Değişiklikleri sakla (stash)…", subtitle: repo.name, icon: "tray.and.arrow.down") {
                    ui.stashRequest += 1
                },
            ]
            for tab in RepoTab.allCases {
                list.append(Item(id: "tab-\(tab.rawValue)", title: "\(tab.rawValue) sekmesi", subtitle: "", icon: "rectangle.on.rectangle") {
                    ui.tab = tab
                })
            }
            list += [
                Item(id: "finder", title: "Finder'da göster", subtitle: repo.name, icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: repo.path)])
                },
                Item(id: "terminal", title: "Terminalde aç", subtitle: repo.name, icon: "terminal") {
                    NSWorkspace.shared.open([URL(fileURLWithPath: repo.path)],
                                            withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"),
                                            configuration: NSWorkspace.OpenConfiguration())
                },
            ]
        }
        list += [
            Item(id: "fetch-all", title: "Bütün depoları getir", subtitle: "\(store.workspace.repos.count) depo",
                 icon: "arrow.triangle.2.circlepath.circle") { store.fetchAll() },
            Item(id: "add", title: "Depo ekle…", subtitle: "", icon: "plus") { AddRepository.present(store: store) },
            Item(id: "folder", title: "Yeni klasör", subtitle: "", icon: "folder.badge.plus") {
                store.edit { $0.createFolder(named: "Yeni klasör") }
            },
        ]
        for repo in store.workspace.repos {
            let s = store.statuses[repo.id]
            let folder = store.workspace.folder(containing: repo.id)?.name
            let detail = [folder, s?.branch].compactMap { $0 }.joined(separator: " · ")
            list.append(Item(id: "repo-\(repo.id)", title: repo.name, subtitle: detail, icon: "shippingbox") {
                store.selection = repo.id
            })
        }
        return list
    }
}
