import HarborCore
import SwiftUI

/// Sol sütun: commit'e hazır ve diğer değişiklikler (tek tıkla ekle/çıkar), altta commit kutusu.
struct ChangesPane: View {
    @Bindable var session: ChangesSession
    @State private var confirmDiscard: [FileChange]?

    var body: some View {
        VStack(spacing: 0) {
            if session.operation != .none {
                ConflictBanner(session: session)
            }
            if session.status.isClean {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                    Text("Çalışma klasörü temiz").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: Binding(get: { session.selected?.id },
                                        set: { id in session.select(session.status.changes.first { $0.id == id }) })) {
                    if !session.staged.isEmpty {
                        Section {
                            ForEach(session.staged) { row($0) }
                        } header: {
                            sectionHeader("Commit'e hazır", count: session.staged.count, action: "Hepsini çıkar") {
                                Task { await session.unstageAll() }
                            }
                        }
                    }
                    if !session.unstaged.isEmpty {
                        Section {
                            ForEach(session.unstaged) { row($0) }
                        } header: {
                            sectionHeader("Değişiklikler", count: session.unstaged.count, action: "Hepsini ekle") {
                                Task { await session.stageAll() }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
            CommitBox(session: session)
        }
        .confirmationDialog("Değişiklikler geri alınsın mı?", isPresented: Binding(get: { confirmDiscard != nil },
                                                                              set: { if !$0 { confirmDiscard = nil } })) {
            Button("Geri Al", role: .destructive) {
                if let items = confirmDiscard { Task { await session.discard(items) } }
                confirmDiscard = nil
            }
        } message: {
            Text("\(confirmDiscard?.count ?? 0) dosyadaki kaydedilmemiş değişiklikler kaybolur. Yeni dosyalar Çöp Sepeti'ne taşınır.")
        }
    }

    private func sectionHeader(_ title: String, count: Int, action: String, perform: @escaping () -> Void) -> some View {
        HStack {
            Text("\(title) · \(count)")
            Spacer()
            Button(action, action: perform)
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .disabled(session.busy)
        }
    }

    private func row(_ change: FileChange) -> some View {
        ChangeRow(change: change) {
            Task { change.staged ? await session.unstage([change]) : await session.stage([change]) }
        }
        .tag(change.id)
        .contextMenu {
            if change.kind == .conflicted {
                Button("Benimkini Kullan") { Task { await session.resolve(change, take: .ours) } }
                Button("Onlarınkini Kullan") { Task { await session.resolve(change, take: .theirs) } }
                Button("Düzenleyicide Aç") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: session.repo.path).appendingPathComponent(change.path))
                }
                Button("Çözüldü Olarak İşaretle") { Task { await session.markResolved(change) } }
                Divider()
            } else if change.staged {
                Button("Commit'ten Çıkar") { Task { await session.unstage([change]) } }
            } else {
                Button("Commit'e Ekle") { Task { await session.stage([change]) } }
                Button("Değişiklikleri Geri Al…", role: .destructive) { confirmDiscard = [change] }
            }
            if change.kind == .untracked || !change.staged {
                Divider()
                Button("Yok Say: \(change.path)") { Task { await session.ignore(change.path) } }
                if let ext = RepoHelpers.extensionPattern(for: change.path) {
                    Button("Yok Say: bütün \(ext) dosyaları") { Task { await session.ignore(ext) } }
                }
            }
            Divider()
            Button("Finder'da Göster") {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: session.repo.path).appendingPathComponent(change.path)])
            }
            Button("Yolu Kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(change.path, forType: .string)
            }
        }
    }
}

private struct ChangeRow: View {
    let change: FileChange
    let toggle: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Text(Theme.letter(change.kind))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 17, height: 17)
                .background(Theme.color(change.kind).gradient, in: RoundedRectangle(cornerRadius: 4.5))
                .help(Theme.label(change.kind))
            VStack(alignment: .leading, spacing: 1) {
                Text(fileName).lineLimit(1)
                if !directory.isEmpty || change.oldPath != nil {
                    Text(change.oldPath.map { "\($0) → " } ?? directory)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 4)
            Button(action: toggle) {
                Image(systemName: change.staged ? "minus.circle.fill" : "plus.circle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(change.staged ? AnyShapeStyle(.secondary) : AnyShapeStyle(Theme.accent))
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0.35)
            .help(change.staged ? "Commit'ten çıkar" : "Commit'e ekle")
            .disabled(change.kind == .conflicted)
        }
        .padding(.vertical, 1)
        .onHover { hovering = $0 }
    }

    private var fileName: String { (change.path as NSString).lastPathComponent }
    private var directory: String { (change.path as NSString).deletingLastPathComponent }
}

/// Commit mesajı (özet + ayrıntı), amend seçeneği ve commit düğmesi.
private struct CommitBox: View {
    @Bindable var session: ChangesSession
    @FocusState private var summaryFocused: Bool
    @State private var showCoAuthors = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Özet (gerekli)", text: $session.summary)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .medium))
                .focused($summaryFocused)
                .onSubmit { Task { await session.commit() } }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .trailing) {
                    let n = session.summary.count
                    if n > 50 {
                        Text("\(n)")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(n > 72 ? Color.red : Theme.behind)
                            .padding(.trailing, 8)
                            .help("Özet 50 karakteri geçmesin")
                    }
                }
            TextEditor(text: $session.details)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: 64)
                .padding(6)
                .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if session.details.isEmpty {
                        Text("Açıklama").font(.system(size: 12)).foregroundStyle(.tertiary)
                            .padding(.horizontal, 11).padding(.vertical, 6).allowsHitTesting(false)
                    }
                }
            if showCoAuthors {
                TextField("Ortak yazar: Ad <e-posta>, …", text: $session.coAuthors)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.background.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Button { showCoAuthors.toggle() } label: {
                    Image(systemName: showCoAuthors ? "person.2.fill" : "person.badge.plus")
                }
                .buttonStyle(.borderless)
                .help("Ortak yazar ekle (Co-authored-by)")
                Toggle("Son commit'i düzelt", isOn: $session.amend)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
                    .help("Amend: değişiklikleri ve mesajı son commit'e katar")
                Spacer()
            }
            Button {
                Task { await session.commit() }
            } label: {
                HStack {
                    if session.busy { ProgressView().controlSize(.small) }
                    Text(buttonTitle).fontWeight(.semibold).lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .disabled(!session.canCommit)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(12)
        .background(.bar)
    }

    private var buttonTitle: String {
        let branch = session.status.branch ?? "HEAD"
        if session.amend { return "Son commit'i düzelt" }
        let n = Set(session.staged.map(\.path)).count
        return n == 0 ? "\(branch) dalına commit" : "\(n) dosyayı \(branch) dalına commit et"
    }
}

/// Birleştirme / rebase sürerken: çakışma sayısı, iptal ve bitir.
private struct ConflictBanner: View {
    let session: ChangesSession

    var body: some View {
        let n = session.conflicts.count
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: n > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(n > 0 ? Theme.color(.conflicted) : Theme.ahead)
                Text(title).font(.system(size: 12, weight: .semibold))
            }
            Text(n > 0 ? "\(n) dosyada çakışma var. Sağ tıkla bir tarafı seç ya da dosyayı düzenleyip çözüldü işaretle."
                       : "Bütün çakışmalar çözüldü. İşlemi bitirebilirsin.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
            HStack {
                Button("İptal et", role: .destructive) { Task { await session.abortOperation() } }
                    .help("İşlemi iptal eder, işlemden önceki duruma döner")
                Spacer()
                Button(n > 0 ? "Çakışmaları çöz" : "Bitir") { Task { await session.continueOperation() } }
                    .buttonStyle(.glassProminent)
                    .disabled(n > 0)
            }
            .disabled(session.busy)
        }
        .padding(12)
        .background(Theme.color(.conflicted).opacity(0.10))
    }

    private var title: String {
        switch session.operation {
        case .merge: "Birleştirme sürüyor"
        case .rebase: "Rebase sürüyor"
        case .cherryPick: "Cherry-pick sürüyor"
        case .revert: "Geri alma (revert) sürüyor"
        case .none: ""
        }
    }
}
