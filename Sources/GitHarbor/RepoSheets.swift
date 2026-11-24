import AppKit
import HarborCore
import SwiftUI

/// Hangi pencere (sheet) açık.
enum RepoSheet: Identifiable {
    case clone, create, publish(UUID)
    var id: String {
        switch self {
        case .clone: "clone"
        case .create: "create"
        case .publish(let id): "publish-\(id)"
        }
    }
}

/// Klasör seçici (tek klasör).
@MainActor
func chooseFolder(_ message: String, initial: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.canCreateDirectories = true
    panel.allowsMultipleSelection = false
    panel.directoryURL = URL(fileURLWithPath: initial)
    panel.message = message
    panel.prompt = "Seç"
    return panel.runModal() == .OK ? panel.url?.path : nil
}

private let defaultParent = NSHomeDirectory() + "/Documents/GitHub"

/// Klonla: GitHub hesabındaki depolar ya da adres.
struct CloneSheet: View {
    let store: HarborStore
    @Environment(\.dismiss) private var dismiss
    // Görsel test: `--clone-urls a,b` adres sekmesini doldurur.
    @State private var tab = value(of: "--clone-urls") == nil ? 0 : 1
    @State private var url = value(of: "--clone-urls")?.replacingOccurrences(of: ",", with: "\n") ?? ""
    @State private var parent = defaultParent
    @State private var repos: [GitHubRepository] = []
    @State private var filter = ""
    @State private var picked: Set<GitHubRepository.ID> = []
    /// Her kaynak için durum: nil bekliyor, "" bitti, metin hata.
    @State private var progress: [String: String?] = [:]
    @State private var loading = false
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Depo klonla").font(.title3.weight(.semibold))
            Picker("", selection: $tab) {
                Text("GitHub'dakilerim").tag(0)
                Text("Adres").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if tab == 0 {
                if store.github.isConnected {
                    TextField("Depo ara", text: $filter).textFieldStyle(.roundedBorder)
                    List(selection: $picked) {
                        ForEach(visible) { r in
                            HStack(spacing: 8) {
                                Image(systemName: r.isPrivate ? "lock.fill" : "book.closed")
                                    .foregroundStyle(.secondary).frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.fullName).lineLimit(1)
                                    if let d = r.description, !d.isEmpty {
                                        Text(d).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                                Spacer()
                                if store.workspace.repos.contains(where: { $0.name == r.name }) {
                                    Text("ekli").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                                }
                            }
                            .tag(r.id)
                        }
                    }
                    .frame(height: 260)
                    .overlay { if loading { ProgressView() } }
                    .task { await load() }
                } else {
                    ConnectCard(account: store.github).frame(height: 300)
                }
            } else {
                Text("Her satıra bir adres").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $url)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 110)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack {
                Text("Klasör:").foregroundStyle(.secondary)
                Text(abbreviate(parent) + "/" + targetLabel).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Değiştir…") { if let p = chooseFolder("Klonun konacağı klasör", initial: parent) { parent = p } }
            }
            .font(.system(size: 12))
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                if working {
                    ProgressView().controlSize(.small)
                    Text("Klonlanıyor… \(finished)/\(sources.count)").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                Button(sources.count > 1 ? "\(sources.count) depoyu klonla" : "Klonla") { Task { await clone() } }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(sources.isEmpty || working)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private var visible: [GitHubRepository] {
        filter.isEmpty ? repos : FuzzyMatch.rank(filter, repos, key: { $0.fullName })
    }

    /// Klonlanacak adresler (liste seçimi ya da satır satır adres).
    private var sources: [String] {
        if tab == 1 {
            var seen = Set<String>()
            return url.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
        }
        return repos.filter { picked.contains($0.id) }.map(\.cloneURL)
    }

    private var targetLabel: String {
        switch sources.count {
        case 0: "…"
        case 1: RepoHelpers.cloneFolderName(sources[0]) ?? "…"
        default: "(\(sources.count) depo)"
        }
    }

    private var finished: Int { progress.values.filter { $0 != nil }.count }

    private func load() async {
        guard repos.isEmpty, let api = store.github.api else { return }
        loading = true
        defer { loading = false }
        do {
            var all: [GitHubRepository] = []
            for page in 1...5 {
                let batch = try await api.repositories(page: page)
                all += batch
                if batch.count < 100 { break }
            }
            repos = all
        } catch {
            self.error = "\(error)"
        }
    }

    /// Seçilenleri en fazla 3'ü aynı anda olacak şekilde klonlar; bitenler hemen eklenir.
    /// Hata olursa pencere açık kalır, hatalı olanlar listelenir.
    private func clone() async {
        let list = sources
        guard !list.isEmpty else { return }
        working = true
        error = nil
        progress = Dictionary(uniqueKeysWithValues: list.map { ($0, String?.none) })
        let target = parent
        await withTaskGroup(of: (String, String?).self) { group in
            var next = 0
            func start() {
                guard next < list.count else { return }
                let src = list[next]
                next += 1
                group.addTask {
                    do {
                        let path = try await Git.clone(src, into: target)
                        await store.addRepositories(at: [URL(fileURLWithPath: path)])
                        return (src, nil)
                    } catch {
                        return (src, "\(error)")
                    }
                }
            }
            for _ in 0..<min(3, list.count) { start() }
            for await (src, failure) in group {
                progress[src] = .some(failure ?? "")
                start()
            }
        }
        working = false
        let failures = list.compactMap { src -> String? in
            guard case let .some(.some(msg)) = progress[src], !msg.isEmpty else { return nil }
            return "\(RepoHelpers.cloneFolderName(src) ?? src): \(msg)"
        }
        if failures.isEmpty {
            dismiss()
        } else {
            error = failures.joined(separator: "\n")
            // Yalnızca başarısız olanlar seçili kalsın (yeniden denemek için).
            let failed = Set(list.filter { if case let .some(.some(m)) = progress[$0] { !m.isEmpty } else { false } })
            picked = picked.filter { id in repos.first { $0.id == id }.map { failed.contains($0.cloneURL) } ?? false }
        }
    }
}

/// Yeni depo: ad, klasör, README, .gitignore şablonu, lisans; isteğe bağlı GitHub'a yayınla.
struct CreateRepoSheet: View {
    let store: HarborStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var parent = defaultParent
    @State private var readme = true
    @State private var gitignore = "Swift"
    @State private var license = "MIT"
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Yeni depo").font(.title3.weight(.semibold))
            Form {
                TextField("Ad", text: $name)
                LabeledContent("Klasör") {
                    HStack {
                        Text(abbreviate(parent)).lineLimit(1).truncationMode(.middle)
                        Button("Değiştir…") { if let p = chooseFolder("Deponun oluşturulacağı klasör", initial: parent) { parent = p } }
                    }
                }
                Toggle("README ekle", isOn: $readme)
                Picker(".gitignore", selection: $gitignore) {
                    Text("Yok").tag("")
                    ForEach(GitignoreTemplates.all.keys.sorted(), id: \.self) { Text($0).tag($0) }
                }
                Picker("Lisans", selection: $license) {
                    Text("Yok").tag("")
                    Text("MIT").tag("MIT")
                }
            }
            .formStyle(.grouped)
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            HStack {
                if working { ProgressView().controlSize(.small) }
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                Button("Oluştur") { Task { await create() } }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func create() async {
        working = true
        defer { working = false }
        do {
            let owner = await Git.identity().name
            let path = try await Git.createRepository(
                name: name, in: parent,
                options: .init(readme: readme, gitignore: gitignore.isEmpty ? nil : gitignore,
                               license: license.isEmpty ? nil : license, owner: owner))
            await store.addRepositories(at: [URL(fileURLWithPath: path)])
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}

/// GitHub'a yayınla: hesapta depo oluşturur, origin ekler, dalı gönderir.
struct PublishSheet: View {
    let store: HarborStore
    let repoID: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = true
    @State private var working = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("GitHub'a yayınla").font(.title3.weight(.semibold))
            if let api = store.github.api {
                Form {
                    TextField("Ad", text: $name)
                    TextField("Açıklama", text: $description)
                    Toggle("Özel (private)", isOn: $isPrivate)
                }
                .formStyle(.grouped)
                if let error { Text(error).font(.caption).foregroundStyle(.orange) }
                HStack {
                    if working { ProgressView().controlSize(.small) }
                    Spacer()
                    Button("Vazgeç", role: .cancel) { dismiss() }
                    Button("Yayınla") { Task { await publish(api) } }
                        .buttonStyle(.glassProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(name.isEmpty || working)
                }
            } else {
                ConnectCard(account: store.github).frame(height: 300)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { name = store.workspace.repo(repoID)?.name.replacingOccurrences(of: " ", with: "-") ?? "" }
    }

    private func publish(_ api: GitHubAPI) async {
        guard let repo = store.workspace.repo(repoID), let branch = store.statuses[repoID]?.branch else {
            error = "Yayınlanacak dal yok (ayrık HEAD ya da commit yok)"
            return
        }
        working = true
        defer { working = false }
        do {
            let created = try await api.createRepository(name: name, description: description, isPrivate: isPrivate)
            try await Git.publish(remoteURL: created.cloneURL, branch: branch, in: repo.path)
            store.refresh(repoID)
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}

func abbreviate(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
}

/// Kurulu kod editörleri (paket kimliğiyle bulunur); tercih UserDefaults'ta.
enum Editors {
    static let known: [(name: String, bundle: String)] = [
        ("Visual Studio Code", "com.microsoft.VSCode"), ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("Xcode", "com.apple.dt.Xcode"), ("Zed", "dev.zed.Zed"), ("Sublime Text", "com.sublimetext.4"),
    ]

    static var installed: [(name: String, bundle: String)] {
        known.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundle) != nil }
    }

    static var preferred: String {
        get { UserDefaults.standard.string(forKey: "editor") ?? installed.first?.bundle ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: "editor") }
    }

    static var preferredName: String { known.first { $0.bundle == preferred }?.name ?? "Editör" }

    @MainActor
    static func open(_ path: String) {
        let target = URL(fileURLWithPath: path)
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: preferred) {
            NSWorkspace.shared.open([target], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(target)
        }
    }
}
