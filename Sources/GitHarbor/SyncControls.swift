import HarborCore
import SwiftUI

/// Başlıktaki ana senkron düğmesi: duruma göre Getir / Çek (N) / Gönder (N) / Yayınla; yanında tüm seçenekler.
struct SyncButton: View {
    let store: HarborStore
    let id: UUID
    let status: RepoStatus
    @Environment(UIState.self) private var ui

    private var state: RepoSyncState { store.sync[id] ?? RepoSyncState() }

    var body: some View {
        HStack(spacing: 0) {
            Button { Task { await primary() } } label: {
                HStack(spacing: 8) {
                    if state.running != nil {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: icon).font(.system(size: 15, weight: .medium)).foregroundStyle(tint)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        Text(subtitle).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                .padding(.leading, 12).padding(.trailing, 8).padding(.vertical, 7)
                .fixedSize()
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state.running != nil)
            .help(help)

            Menu {
                Button("Getir (fetch)") { Task { await store.fetch(id) } }
                Divider()
                Button("Çek: birleştir (merge)") { Task { await store.pull(id, mode: .merge) } }
                    .disabled(status.upstream == nil)
                Button("Çek: yeniden temellendir (rebase)") { Task { await store.pull(id, mode: .rebase) } }
                    .disabled(status.upstream == nil)
                Divider()
                Button(status.upstream == nil ? "Dalı yayınla" : "Gönder (push)") { Task { await store.push(id) } }
                    .disabled(status.branch == nil)
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .padding(.trailing, 10)
            .disabled(state.running != nil)
        }
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 10))
    }

    private enum Action { case fetch, pull, push, publish }

    private var action: Action {
        if status.branch != nil && status.upstream == nil { return .publish }
        if status.behind > 0 { return .pull }
        if status.ahead > 0 { return .push }
        return .fetch
    }

    private func primary() async {
        switch action {
        case .fetch: await store.fetch(id)
        case .pull: await store.pull(id, mode: .merge)
        case .push: await store.push(id)
        case .publish:
            // Uzağı olmayan depo: önce GitHub'da oluştur.
            if let repo = store.workspace.repo(id), await Git.remotes(in: repo.path).isEmpty {
                ui.sheet = .publish(id)
            } else {
                await store.push(id)
            }
        }
    }

    private var icon: String {
        switch action {
        case .fetch: "arrow.triangle.2.circlepath"
        case .pull: "arrow.down.circle.fill"
        case .push: "arrow.up.circle.fill"
        case .publish: "icloud.and.arrow.up"
        }
    }

    private var tint: Color {
        switch action {
        case .fetch: .secondary
        case .pull: Theme.behind
        case .push, .publish: Theme.ahead
        }
    }

    private var title: String {
        switch state.running {
        case .fetching: return "Getiriliyor…"
        case .pulling: return "Çekiliyor…"
        case .pushing: return "Gönderiliyor…"
        case nil: break
        }
        switch action {
        case .fetch: return "Getir"
        case .pull: return status.ahead > 0 ? "Çek \(status.behind) · gönder \(status.ahead)" : "Çek (\(status.behind))"
        case .push: return "Gönder (\(status.ahead))"
        case .publish: return "Dalı yayınla"
        }
    }

    private var subtitle: String {
        if let last = state.lastFetch {
            return "getirildi " + last.formatted(.relative(presentation: .named))
        }
        return status.upstream ?? "uzakta yok"
    }

    private var help: String {
        switch action {
        case .fetch: "Uzak depodaki yenilikleri getir"
        case .pull: "Uzak değişiklikleri bu dala çek"
        case .push: "Yerel commit'leri uzak depoya gönder"
        case .publish: "Bu dalı uzak depoda oluştur ve izle"
        }
    }
}

/// Başlığın altında: otomatik çekilemeyen değişiklik ya da senkron hatası.
struct SyncBanner: View {
    let store: HarborStore
    let id: UUID

    var body: some View {
        let state = store.sync[id] ?? RepoSyncState()
        if let error = state.error {
            banner(icon: "exclamationmark.triangle.fill", color: .orange, text: error) {
                store.clearSyncError(id)
            }
        } else if let reason = state.attention {
            banner(icon: "arrow.down.circle.fill", color: Theme.behind,
                   text: "Çekilecek değişiklik var, otomatik çekilmedi: \(reason)", dismiss: nil)
        }
    }

    private func banner(icon: String, color: Color, text: String, dismiss: (() -> Void)?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.system(size: 11.5)).lineLimit(2).textSelection(.enabled)
            Spacer()
            if let dismiss {
                Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 22).padding(.vertical, 7)
        .background(color.opacity(0.10))
    }
}

/// Genel git kimliği (user.name, user.email).
struct IdentityEditor: View {
    @State private var name = ""
    @State private var email = ""
    @State private var saved = ""

    var body: some View {
        TextField("Ad", text: $name)
        TextField("E-posta", text: $email)
        HStack {
            Text(saved).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button("Kaydet") {
                Task {
                    do { try await Git.setIdentity(name: name, email: email); saved = "Kaydedildi" }
                    catch { saved = "\(error)" }
                }
            }
            .disabled(name.isEmpty || email.isEmpty)
        }
        .task {
            let id = await Git.identity()
            name = id.name
            email = id.email
        }
    }
}
