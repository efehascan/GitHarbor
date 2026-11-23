import HarborCore
import SwiftUI

/// Pull request sekmesi: liste (CI rozetiyle), ayrıntı (açıklama, kontroller), yerelde aç, yeni PR.
struct PullRequestsView: View {
    let account: GitHubAccount
    @Bindable var session: PullRequestSession
    let status: RepoStatus
    @State private var creating = false

    var body: some View {
        Group {
            if let api = account.api {
                content(api)
            } else {
                ConnectCard(account: account)
            }
        }
        .alert("İşlem yapılamadı", isPresented: Binding(get: { session.lastError != nil && account.isConnected },
                                                       set: { if !$0 { session.lastError = nil } })) {
            Button("Tamam", role: .cancel) {}
        } message: { Text(session.lastError ?? "") }
    }

    @ViewBuilder
    private func content(_ api: GitHubAPI) -> some View {
        if session.resolved && session.repoID == nil {
            placeholder("questionmark.folder", "Bu deponun uzağı GitHub'da değil")
        } else {
            HSplitView {
                VStack(spacing: 0) {
                    listHeader(api)
                    Divider()
                    List(selection: Binding(get: { session.selected?.number },
                                            set: { n in Task { await session.select(session.pulls.first { $0.number == n }, api: api) } })) {
                        ForEach(session.pulls) { pr in
                            PRRow(pr: pr, summary: session.summaries[pr.head.sha] ?? .none,
                                  isCurrent: pr.head.ref == status.branch)
                                .tag(pr.number)
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                    .overlay {
                        if session.pulls.isEmpty && !session.loading {
                            Text("Açık pull request yok").foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 520)
                PRDetail(session: session, api: api)
                    .frame(minWidth: 380, maxWidth: .infinity)
            }
            .task { await session.load(api: api) }
            .sheet(isPresented: $creating) {
                CreatePRSheet(session: session, api: api, status: status)
            }
        }
    }

    private func listHeader(_ api: GitHubAPI) -> some View {
        HStack(spacing: 8) {
            if let id = session.repoID {
                Text(id.slug).font(.system(size: 11.5, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if session.loading { ProgressView().controlSize(.small) }
            Button { Task { await session.load(api: api) } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help("Yenile")
            Button { creating = true } label: { Label("Yeni PR", systemImage: "plus") }
                .buttonStyle(.glass)
                .disabled(status.branch == nil || status.branch == session.defaultBranch || session.pull(forBranch: status.branch) != nil)
                .help(createHelp)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private var createHelp: String {
        if status.branch == nil { return "Ayrık HEAD'den PR açılamaz" }
        if status.branch == session.defaultBranch { return "Varsayılan daldan PR açılmaz; önce yeni bir dal oluştur" }
        if session.pull(forBranch: status.branch) != nil { return "Bu dalın zaten açık bir PR'ı var" }
        return "\(status.branch ?? "") dalından pull request aç"
    }

    private func placeholder(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// GitHub'a bağlanma kartı (PR sekmesinde ve ayarlarda).
struct ConnectCard: View {
    let account: GitHubAccount
    @State private var token = ""

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.accent.gradient)
            Text("GitHub'a bağlan").font(.title3.weight(.semibold))
            Text("Depolarını klonlamak, pull request'leri ve CI durumunu görmek için. Token macOS Anahtar Zinciri'nde saklanır.")
                .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 340)
            if account.cliAvailable {
                Button { Task { await account.connectWithCLI() } } label: {
                    Label("GitHub CLI oturumunu kullan", systemImage: "terminal")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
            HStack {
                SecureField("ya da kişisel erişim token'ı", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                Button("Bağlan") { let t = token; token = ""; Task { await account.connect(token: t) } }
                    .disabled(token.isEmpty)
            }
            if account.connecting { ProgressView().controlSize(.small) }
            if let error = account.lastError {
                Text(error).font(.caption).foregroundStyle(.orange).multilineTextAlignment(.center).frame(maxWidth: 360)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PRRow: View {
    let pr: PullRequest
    let summary: CheckSummary
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: pr.draft ? "circle.dashed" : "arrow.triangle.pull")
                .foregroundStyle(pr.draft ? Color.secondary : Theme.ahead)
                .font(.system(size: 13, weight: .medium))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(pr.title).lineLimit(2)
                HStack(spacing: 5) {
                    Text("#\(pr.number)")
                    Text("·")
                    Text(pr.user.login)
                    Text("·")
                    Text(pr.updatedAt, format: .relative(presentation: .named))
                }
                .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                HStack(spacing: 4) {
                    RefChip(text: pr.head.ref)
                    if isCurrent {
                        Text("mevcut dal").font(.system(size: 9.5, weight: .semibold)).foregroundStyle(Theme.accent)
                    }
                }
            }
            Spacer(minLength: 4)
            CheckBadge(summary: summary)
        }
        .padding(.vertical, 3)
    }
}

struct CheckBadge: View {
    let summary: CheckSummary

    var body: some View {
        switch summary {
        case .none:
            EmptyView()
        case .pending(let done, let total):
            Image(systemName: "circle.dotted").foregroundStyle(Theme.behind).help("CI sürüyor: \(done)/\(total)")
        case .success(let total):
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ahead).help("\(total) kontrol başarılı")
        case .failure(let failed, let total):
            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.color(.deleted)).help("\(failed)/\(total) kontrol başarısız")
        }
    }
}

private struct PRDetail: View {
    let session: PullRequestSession
    let api: GitHubAPI

    var body: some View {
        if let pr = session.selected {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pr.title).font(.system(size: 17, weight: .semibold)).textSelection(.enabled)
                        HStack(spacing: 6) {
                            Text("#\(pr.number)").foregroundStyle(.secondary)
                            if pr.draft { Text("Taslak").font(.caption.weight(.semibold)).foregroundStyle(.secondary) }
                            Text(pr.user.login).fontWeight(.medium)
                            Text("şunu birleştirmek istiyor:").foregroundStyle(.secondary)
                            RefChip(text: pr.head.ref)
                            Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                            RefChip(text: pr.base.ref)
                        }
                        .font(.system(size: 11.5))
                    }
                    HStack {
                        Button { Task { await session.checkout(pr) } } label: {
                            Label("Yerelde aç", systemImage: "arrow.down.to.line")
                        }
                        .buttonStyle(.glassProminent)
                        .help("PR dalını getirip ona geçer")
                        Button {
                            if let url = URL(string: pr.htmlURL) { NSWorkspace.shared.open(url) }
                        } label: { Label("GitHub'da aç", systemImage: "safari") }
                        .buttonStyle(.glass)
                        if session.busy { ProgressView().controlSize(.small) }
                    }
                    if !session.checks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Kontroller").font(.headline)
                            ForEach(session.checks) { run in
                                HStack(spacing: 8) {
                                    CheckBadge(summary: GitHubParsing.summarize([run]))
                                    Text(run.name).lineLimit(1)
                                    Spacer()
                                    Text(run.conclusion ?? (run.status == "queued" ? "sırada" : "sürüyor"))
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let link = run.htmlURL, let url = URL(string: link) {
                                        Button { NSWorkspace.shared.open(url) } label: { Image(systemName: "arrow.up.right.square") }
                                            .buttonStyle(.borderless)
                                    }
                                }
                                .font(.system(size: 12))
                            }
                        }
                        .padding(12)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let body = pr.body, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(markdown(body, repo: session.repoID))
                            .font(.system(size: 12.5))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("Açıklama yok").foregroundStyle(.tertiary)
                    }
                }
                .padding(18)
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
        } else {
            Text("Bir pull request seç").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Markdown + "#123" referanslarını GitHub bağlantısına çevirir.
func markdown(_ text: String, repo: GitHubRepoID?) -> AttributedString {
    var source = text
    if let repo {
        for n in GitHubParsing.issueNumbers(in: text) {
            source = source.replacingOccurrences(of: "#\(n)", with: "[#\(n)](https://github.com/\(repo.slug)/issues/\(n))")
        }
    }
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: source, options: options)) ?? AttributedString(text)
}

private struct CreatePRSheet: View {
    let session: PullRequestSession
    let api: GitHubAPI
    let status: RepoStatus
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @State private var base = ""
    @State private var draft = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yeni pull request").font(.title3.weight(.semibold))
            HStack(spacing: 6) {
                RefChip(text: status.branch ?? "")
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                TextField("hedef dal", text: $base).textFieldStyle(.roundedBorder).frame(width: 160)
            }
            if status.upstream == nil {
                Label("Dal henüz uzakta yok; PR açılırken yayınlanacak.", systemImage: "icloud.and.arrow.up")
                    .font(.caption).foregroundStyle(.secondary)
            } else if status.ahead > 0 {
                Label("\(status.ahead) commit önce gönderilecek.", systemImage: "arrow.up.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField("Başlık", text: $title).textFieldStyle(.roundedBorder)
            TextEditor(text: $body_)
                .font(.system(size: 12.5))
                .frame(height: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Toggle("Taslak olarak aç", isOn: $draft)
            HStack {
                if session.busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Vazgeç", role: .cancel) { dismiss() }
                Button("Pull request aç") {
                    Task {
                        if await session.create(api: api, status: status, title: title, body: body_, base: base, draft: draft) != nil {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || base.isEmpty || session.busy)
            }
            if let error = session.lastError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            base = session.defaultBranch ?? "main"
            if let last = status.branch { title = last.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "/", with: ": ") }
        }
    }
}
