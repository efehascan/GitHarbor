import HarborCore
import SwiftUI

/// Sağ sütun: seçili dosyanın farkı. Satıra tıkla seç (⇧ ile aralık), parça başlığına tıkla parçayı seç;
/// seçili satırlar commit'e eklenir/çıkarılır ya da geri alınır.
struct DiffPane: View {
    @Bindable var session: ChangesSession
    @State private var confirmDiscard = false

    var body: some View {
        VStack(spacing: 0) {
            if let change = session.selected {
                toolbar(change)
                Divider()
                if let diff = session.diff {
                    if diff.isBinary {
                        placeholder("doc.zipper", "İkili dosya: fark gösterilemiyor")
                    } else if diff.hunks.isEmpty {
                        placeholder("doc", diff.oldPath != diff.newPath ? "Sadece yeniden adlandırıldı" : "İçerik değişikliği yok (kip değişti)")
                    } else {
                        lines(diff)
                    }
                } else if session.diffLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    placeholder("doc", "Fark yok")
                }
            } else {
                placeholder("doc.text.magnifyingglass", "Farkı görmek için bir dosya seç")
            }
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
        .confirmationDialog("Seçili satırlar geri alınsın mı?", isPresented: $confirmDiscard) {
            Button("Geri Al", role: .destructive) { Task { await session.discardSelection() } }
        } message: {
            Text("Bu satırlardaki kaydedilmemiş değişiklik kaybolur.")
        }
    }

    private func toolbar(_ change: FileChange) -> some View {
        HStack(spacing: 10) {
            Text(change.path)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(change.staged ? "commit'e hazır" : Theme.label(change.kind).lowercased())
                .font(.system(size: 10.5, weight: .medium))
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Theme.color(change.kind).opacity(0.18), in: Capsule())
                .foregroundStyle(Theme.color(change.kind))
            Spacer()
            if !session.lineSelection.isEmpty {
                Text("\(session.lineSelection.count) satır").font(.system(size: 11)).foregroundStyle(.secondary)
                Button(change.staged ? "Seçileni çıkar" : "Seçileni ekle") {
                    Task { await session.applySelectionToIndex() }
                }
                .buttonStyle(.glass)
                if !change.staged, change.kind != .untracked {
                    Button("Geri al…", role: .destructive) { confirmDiscard = true }
                        .buttonStyle(.glass)
                }
                Button { session.lineSelection = [] } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help("Seçimi temizle")
            } else {
                Text("Satırlara tıklayarak seç").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .disabled(session.busy)
    }

    private func lines(_ diff: FileDiff) -> some View {
        ScrollView([.vertical, .horizontal]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: []) {
                ForEach(Array(diff.hunks.enumerated()), id: \.offset) { h, hunk in
                    HunkHeader(hunk: hunk, selected: !PatchBuilder.changeRefs(in: diff, hunk: h).isDisjoint(with: session.lineSelection)) {
                        session.selectHunk(h)
                    }
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { i, line in
                        let ref = DiffLineRef(hunk: h, line: i)
                        DiffLineRow(line: line, selected: session.lineSelection.contains(ref))
                            .onTapGesture {
                                session.toggleLine(ref, extend: NSEvent.modifierFlags.contains(.shift))
                            }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .defaultScrollAnchor(.topLeading)
    }

    private func placeholder(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct HunkHeader: View {
    let hunk: DiffHunk
    let selected: Bool
    let tap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(selected ? Theme.accent : Color.secondary)
            Text("@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@ \(hunk.section)")
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(minWidth: 600, alignment: .leading)
        .background(Theme.accent.opacity(0.07))
        .contentShape(Rectangle())
        .onTapGesture(perform: tap)
        .help("Parçanın bütün değişikliklerini seç")
    }
}

private struct DiffLineRow: View {
    let line: DiffLine
    let selected: Bool

    var body: some View {
        HStack(spacing: 0) {
            number(line.oldNumber)
            number(line.newNumber)
            Rectangle()
                .fill(selected ? Theme.accent : Color.clear)
                .frame(width: 3)
            Text(marker)
                .frame(width: 18)
                .foregroundStyle(markerColor)
            Text(line.text.isEmpty ? " " : line.text)
                .foregroundStyle(line.kind == .noNewline ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                .fixedSize()
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, design: .monospaced))
        .frame(minWidth: 600, minHeight: 19, alignment: .leading)
        .background(background)
        .contentShape(Rectangle())
    }

    private func number(_ n: Int?) -> some View {
        Text(n.map(String.init) ?? "")
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(.tertiary)
            .frame(width: 42, alignment: .trailing)
            .padding(.trailing, 6)
    }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        case .context, .noNewline: ""
        }
    }

    private var markerColor: Color {
        line.kind == .added ? Theme.color(.added) : Theme.color(.deleted)
    }

    private var background: Color {
        let base: Color
        switch line.kind {
        case .added: base = Theme.color(.added).opacity(selected ? 0.32 : 0.13)
        case .removed: base = Theme.color(.deleted).opacity(selected ? 0.32 : 0.13)
        case .context, .noNewline: base = .clear
        }
        return base
    }
}
