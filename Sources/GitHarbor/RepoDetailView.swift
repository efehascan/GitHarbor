import HarborCore
import SwiftUI

/// Seçili deponun başlığı (dal, senkron durumu) ve değişiklik listesi.
/// Fark görünümü ve commit 2. aşamada bu ekrana eklenecek.
struct RepoDetailView: View {
    let repo: RepoEntry
    let status: RepoStatus?
    let error: String?
    @State private var selected: FileChange.ID?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error {
                message("exclamationmark.triangle", error)
            } else if let status {
                if status.isClean {
                    message("checkmark.seal", "Çalışma klasörü temiz")
                } else {
                    changeList(status)
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(repo.name)
        .navigationSubtitle(status?.branch ?? "")
    }

    private var header: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(repo.name).font(.title2.weight(.semibold))
                Text(abbreviated(repo.path))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            if let status {
                Pill(icon: "arrow.triangle.branch", title: status.branch ?? "ayrık HEAD",
                     detail: status.upstream ?? "yayınlanmamış dal")
                Pill(icon: "arrow.down.circle", title: "\(status.behind) gelen",
                     detail: status.behind > 0 ? "çekilecek" : "güncel", tint: status.behind > 0 ? Theme.behind : nil)
                Pill(icon: "arrow.up.circle", title: "\(status.ahead) giden",
                     detail: status.ahead > 0 ? "gönderilecek" : "gönderilecek yok", tint: status.ahead > 0 ? Theme.ahead : nil)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private func changeList(_ status: RepoStatus) -> some View {
        let staged = status.changes.filter(\.staged)
        let unstaged = status.changes.filter { !$0.staged }
        return List(selection: $selected) {
            if !staged.isEmpty {
                Section("Commit'e hazır · \(staged.count)") {
                    ForEach(staged) { ChangeRow(change: $0).tag($0.id) }
                }
            }
            if !unstaged.isEmpty {
                Section("Değişiklikler · \(unstaged.count)") {
                    ForEach(unstaged) { ChangeRow(change: $0).tag($0.id) }
                }
            }
        }
        .listStyle(.inset)
        .scrollContentBackground(.hidden)
    }

    private func message(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func abbreviated(_ path: String) -> String {
        let home = NSHomeDirectory()
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }
}

private struct Pill: View {
    let icon: String
    let title: String
    let detail: String
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint ?? .secondary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Text(detail).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
    }
}

private struct ChangeRow: View {
    let change: FileChange

    var body: some View {
        HStack(spacing: 10) {
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
        }
        .padding(.vertical, 1)
    }

    private var fileName: String { (change.path as NSString).lastPathComponent }
    private var directory: String { (change.path as NSString).deletingLastPathComponent }
}
