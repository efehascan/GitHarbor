import HarborCore
import SwiftUI

/// Geçmiş: solda commit listesi (sayfalı), sağda seçili commit'in mesajı, dosyaları ve farkı.
struct HistoryView: View {
    @Bindable var session: HistorySession
    @State private var tagTarget: CommitInfo?
    @State private var branchTarget: CommitInfo?
    @State private var nameDraft = ""
    @State private var confirmRevert: CommitInfo?

    var body: some View {
        HSplitView {
            commitList
                .frame(minWidth: 300, idealWidth: 380, maxWidth: 520)
            CommitDetail(session: session)
                .frame(minWidth: 380, maxWidth: .infinity)
        }
        .alert("Yeni etiket", isPresented: Binding(get: { tagTarget != nil }, set: { if !$0 { tagTarget = nil } })) {
            TextField("v1.0.0", text: $nameDraft)
            Button("Oluştur") {
                if let c = tagTarget { let n = nameDraft; Task { await session.createTag(n, at: c, message: nil) } }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { Text(tagTarget.map { "\($0.shortSHA) · \($0.subject)" } ?? "") }
        .alert("Buradan yeni dal", isPresented: Binding(get: { branchTarget != nil }, set: { if !$0 { branchTarget = nil } })) {
            TextField("dal-adı", text: $nameDraft)
            Button("Oluştur ve geç") {
                if let c = branchTarget { let n = nameDraft; Task { await session.createBranch(n, from: c.sha) } }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: { Text(branchTarget.map { "\($0.shortSHA) · \($0.subject)" } ?? "") }
        .confirmationDialog("Bu commit geri alınsın mı?", isPresented: Binding(get: { confirmRevert != nil },
                                                                             set: { if !$0 { confirmRevert = nil } })) {
            Button("Geri alan commit oluştur") { if let c = confirmRevert { Task { await session.revert(c) } } }
        } message: {
            Text("Geçmiş silinmez; bu commit'in değişikliklerini tersine çeviren yeni bir commit eklenir.")
        }
    }

    private var commitList: some View {
        List(selection: Binding(get: { session.selected?.sha },
                                set: { sha in Task { await session.select(session.commits.first { $0.sha == sha }) } })) {
            ForEach(session.commits) { commit in
                CommitRow(commit: commit, tags: session.tags(for: commit.sha))
                    .tag(commit.sha)
                    .contextMenu { menu(commit) }
                    .onAppear {
                        if commit.sha == session.commits.last?.sha { Task { await session.loadMore() } }
                    }
            }
            if session.loading {
                ProgressView().frame(maxWidth: .infinity)
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
        .overlay {
            if session.commits.isEmpty && !session.loading {
                Text("Henüz commit yok").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func menu(_ commit: CommitInfo) -> some View {
        Button("SHA'yı Kopyala") { copy(commit.sha) }
        Button("Özeti Kopyala") { copy(commit.subject) }
        Divider()
        Button("Buradan Dal Oluştur…") { nameDraft = ""; branchTarget = commit }
        Button("Etiket Oluştur…") { nameDraft = ""; tagTarget = commit }
        Divider()
        Button("Mevcut Dala Al (cherry-pick)") { Task { await session.cherryPick(commit) } }
        Button("Geri Al (revert)…") { confirmRevert = commit }
        Divider()
        Button("Bu Commit'e Geç (ayrık HEAD)") { Task { await session.checkout(commit) } }
        ForEach(session.tags(for: commit.sha), id: \.self) { tag in
            Divider()
            Button("\"\(tag)\" etiketini gönder") { Task { await session.pushTag(tag) } }
            Button("\"\(tag)\" etiketini sil", role: .destructive) { Task { await session.deleteTag(tag) } }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct CommitRow: View {
    let commit: CommitInfo
    let tags: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                if commit.isMerge {
                    Image(systemName: "arrow.triangle.merge").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Text(commit.subject).lineLimit(1)
            }
            HStack(spacing: 6) {
                Avatar(name: commit.author)
                Text(commit.author).lineLimit(1)
                Text("·")
                Text(commit.date, format: .relative(presentation: .named)).lineLimit(1)
                Spacer(minLength: 4)
                ForEach(chips, id: \.self) { RefChip(text: $0) }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    /// Dal ve etiket çipleri (HEAD işareti ayrı gösterilmez).
    private var chips: [String] {
        commit.refs.compactMap { ref in
            if ref.hasPrefix("HEAD -> ") { return String(ref.dropFirst(8)) }
            if ref == "HEAD" || ref.hasSuffix("/HEAD") { return nil }
            if ref.hasPrefix("tag: ") { return nil }
            return ref
        } + tags.map { "🏷 " + $0 }
    }
}

struct RefChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1.5)
            .background((text.contains("/") && !text.hasPrefix("🏷") ? Color.secondary : Theme.accent).opacity(0.16), in: Capsule())
            .foregroundStyle(text.contains("/") && !text.hasPrefix("🏷") ? Color.secondary : Theme.accent)
    }
}

struct Avatar: View {
    let name: String
    var body: some View {
        Text(initials)
            .font(.system(size: 7.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 15, height: 15)
            .background(color.gradient, in: Circle())
    }

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    private var color: Color {
        let hues: [Double] = [0.58, 0.02, 0.33, 0.75, 0.12, 0.47, 0.88]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return Color(hue: hues[sum % hues.count], saturation: 0.55, brightness: 0.8)
    }
}

/// Seçili commit: başlık, mesaj, değişen dosyalar ve salt okunur fark.
private struct CommitDetail: View {
    @Bindable var session: HistorySession

    var body: some View {
        if let commit = session.selected {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.message.components(separatedBy: "\n").first ?? commit.subject)
                        .font(.system(size: 15, weight: .semibold))
                        .textSelection(.enabled)
                    let body = session.message.components(separatedBy: "\n").dropFirst().joined(separator: "\n")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !body.isEmpty {
                        Text(body).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                            .lineLimit(8)
                    }
                    HStack(spacing: 8) {
                        Avatar(name: commit.author)
                        Text(commit.author).font(.system(size: 11.5, weight: .medium))
                        Text(commit.date.formatted(date: .abbreviated, time: .shortened))
                        Spacer()
                        Text(commit.shortSHA).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                        Text("\(session.files.count) dosya")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                Divider()
                if session.files.isEmpty {
                    Text("Bu commit'te dosya değişikliği yok").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VSplitView {
                        List(selection: Binding(get: { session.selectedFile }, set: { session.selectedFile = $0 ?? 0 })) {
                            ForEach(Array(session.files.enumerated()), id: \.offset) { i, file in
                                FileLine(file: file).tag(i)
                            }
                        }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 70, idealHeight: 130, maxHeight: 260)
                        if session.files.indices.contains(session.selectedFile) {
                            ReadOnlyDiff(file: session.files[session.selectedFile])
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
        } else {
            Text("Bir commit seç").foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct FileLine: View {
    let file: FileDiff
    var body: some View {
        let kind: ChangeKind = file.isNewFile ? .added : file.isDeletedFile ? .deleted
            : (file.oldPath != file.newPath ? .renamed : .modified)
        let added = file.hunks.flatMap(\.lines).filter { $0.kind == .added }.count
        let removed = file.hunks.flatMap(\.lines).filter { $0.kind == .removed }.count
        HStack(spacing: 8) {
            Text(Theme.letter(kind))
                .font(.system(size: 9.5, weight: .bold, design: .rounded)).foregroundStyle(.white)
                .frame(width: 15, height: 15)
                .background(Theme.color(kind).gradient, in: RoundedRectangle(cornerRadius: 4))
            Text(file.newPath ?? file.oldPath ?? "").font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
            Spacer()
            if added > 0 { Text("+\(added)").foregroundStyle(Theme.color(.added)) }
            if removed > 0 { Text("−\(removed)").foregroundStyle(Theme.color(.deleted)) }
        }
        .font(.system(size: 10.5, weight: .medium).monospacedDigit())
    }
}

/// Seçim yapılamayan fark görünümü (geçmiş için).
struct ReadOnlyDiff: View {
    let file: FileDiff
    var body: some View {
        if file.isBinary {
            Text("İkili dosya").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView([.vertical, .horizontal]) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
                        Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@ \(hunk.section)")
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .frame(minWidth: 600, alignment: .leading)
                            .background(Theme.accent.opacity(0.07))
                        ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                            DiffLineView(line: line, selected: false)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
            .defaultScrollAnchor(.topLeading)
        }
    }
}
