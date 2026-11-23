import AppKit
import HarborCore
import SwiftUI
import UserNotifications

/// Uygulama teması (UserDefaults "theme": system | light | dark).
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "Sistem"
        case .light: "Açık"
        case .dark: "Koyu"
        }
    }
    var icon: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }

    @MainActor
    static var current: AppTheme {
        get { AppTheme(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .system }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "theme"); newValue.apply() }
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// Ayarlar penceresi (⌘, ya da araç çubuğundaki dişli).
struct SettingsView: View {
    let store: HarborStore
    @AppStorage("settingsTab") private var tab = "genel"

    var body: some View {
        TabView(selection: $tab) {
            GeneralPane().tabItem { Label("Genel", systemImage: "gearshape") }.tag("genel")
            SyncPane(store: store).tabItem { Label("Senkron", systemImage: "arrow.triangle.2.circlepath") }.tag("senkron")
            NotificationsPane(store: store).tabItem { Label("Bildirimler", systemImage: "bell.badge") }.tag("bildirim")
            GitHubPane(store: store).tabItem { Label("GitHub", systemImage: "person.crop.circle") }.tag("github")
            GitPane().tabItem { Label("Git", systemImage: "arrow.triangle.branch") }.tag("git")
        }
        .frame(width: 520, height: 430)
    }
}

private struct GeneralPane: View {
    @State private var theme = AppTheme.current
    @State private var editor = Editors.preferred

    var body: some View {
        Form {
            Section("Görünüm") {
                Picker("Tema", selection: $theme) {
                    ForEach(AppTheme.allCases) { t in Label(t.title, systemImage: t.icon).tag(t) }
                }
                .pickerStyle(.segmented)
                .onChange(of: theme) { AppTheme.current = theme }
            }
            Section("Editör") {
                Picker("Kod editörü", selection: $editor) {
                    ForEach(Editors.installed, id: \.bundle) { Text($0.name).tag($0.bundle) }
                }
                .disabled(Editors.installed.isEmpty)
                .onChange(of: editor) { Editors.preferred = editor }
                if Editors.installed.isEmpty {
                    Text("Bilinen bir editör bulunamadı; dosyalar varsayılan uygulamayla açılır.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct SyncPane: View {
    let store: HarborStore

    var body: some View {
        Form {
            Section("Otomatik senkron") {
                Toggle("Uzak depoları otomatik getir (fetch)", isOn: binding(\.autoFetch))
                Picker("Sıklık", selection: binding(\.interval)) {
                    ForEach([60.0, 300, 900, 1800, 3600], id: \.self) { s in
                        Text(AutoSyncPolicy.intervalLabel(s)).tag(s)
                    }
                }
                .disabled(!store.settings.autoFetch)
                Toggle("Güvenliyse otomatik çek (pull)", isOn: binding(\.autoPull))
                    .disabled(!store.settings.autoFetch)
                Text("Yalnızca çalışma klasörü temizken ve yerel commit yokken ileri sarılır; aksi halde depoda uyarı gösterilir. Senin işin hiçbir zaman değiştirilmez.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Düşük güç modunda duraklat", isOn: binding(\.pauseOnLowPower))
            }
            Section {
                Button("Bütün depoları şimdi getir") { store.fetchAll() }
            }
        }
        .formStyle(.grouped)
    }

    private func binding<T>(_ path: WritableKeyPath<SyncSettings, T>) -> Binding<T> {
        Binding(get: { store.settings[keyPath: path] }, set: { v in store.updateSettings { $0[keyPath: path] = v } })
    }
}

private struct NotificationsPane: View {
    let store: HarborStore
    @State private var status: UNAuthorizationStatus = .notDetermined
    @State private var sent = false

    var body: some View {
        Form {
            Section("Bildirimler") {
                Toggle("Bildirim gönder", isOn: Binding(get: { store.settings.notify },
                                                       set: { v in store.updateSettings { $0.notify = v } }))
                Text("Bir depo otomatik çekildiğinde (\"2 yeni commit main dalına çekildi\") ve çekilecek değişiklik olup otomatik çekilemediğinde.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("macOS izni") {
                LabeledContent("Durum") {
                    Label(statusText, systemImage: statusIcon).foregroundStyle(statusColor)
                }
                HStack {
                    if status == .notDetermined {
                        Button("İzin iste") { Task { await request() } }
                    }
                    Button("Sistem Ayarları'nda aç") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Spacer()
                    Button(sent ? "Gönderildi" : "Deneme bildirimi") {
                        Notifier.test()
                        sent = true
                    }
                    .disabled(status == .denied || !store.settings.notify)
                }
                if Bundle.main.bundleIdentifier == nil {
                    Text("Paketlenmemiş çalıştırmada (swift run) bildirim gönderilemez; dist'teki uygulamayı kullan.")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
        .task { await refresh() }
    }

    private var statusText: String {
        switch status {
        case .authorized, .provisional, .ephemeral: "İzin verildi"
        case .denied: "Kapalı (Sistem Ayarları'ndan aç)"
        case .notDetermined: "Henüz sorulmadı"
        @unknown default: "Bilinmiyor"
        }
    }
    private var statusIcon: String { status == .denied ? "bell.slash" : status == .notDetermined ? "bell" : "bell.badge.fill" }
    private var statusColor: Color { status == .denied ? .orange : status == .notDetermined ? .secondary : Theme.ahead }

    private func refresh() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        status = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    private func request() async {
        guard Bundle.main.bundleIdentifier != nil else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        await refresh()
    }
}

private struct GitHubPane: View {
    let store: HarborStore

    var body: some View {
        Form {
            Section("Hesap") {
                if let user = store.github.user {
                    LabeledContent("Bağlı hesap") { Label(user.login, systemImage: "checkmark.seal.fill").foregroundStyle(Theme.ahead) }
                    Button("Bağlantıyı kes", role: .destructive) { store.github.signOut() }
                    Text("Token Anahtar Zinciri'nden silinir. GitHub CLI oturumun etkilenmez.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if store.github.isConnected {
                    LabeledContent("Hesap", value: "bağlı (doğrulanıyor)")
                    Button("Bağlantıyı kes", role: .destructive) { store.github.signOut() }
                } else {
                    ConnectCard(account: store.github).frame(height: 300)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct GitPane: View {
    var body: some View {
        Form {
            Section("Kimlik (genel git ayarı)") {
                IdentityEditor()
            }
            Section {
                Text("Commit'lerde görünen ad ve e-posta. Bütün depolar için geçerlidir (git config --global).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
