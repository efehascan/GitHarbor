import HarborCore
import SwiftUI

enum Theme {
    static let accent = Color(red: 0.18, green: 0.52, blue: 0.96)
    static let ahead = Color(red: 0.20, green: 0.70, blue: 0.45)
    static let behind = Color(red: 0.95, green: 0.60, blue: 0.15)

    static func color(_ kind: ChangeKind) -> Color {
        switch kind {
        case .added, .untracked: Color(red: 0.22, green: 0.72, blue: 0.42)
        case .modified, .typeChanged: Color(red: 0.95, green: 0.66, blue: 0.16)
        case .deleted: Color(red: 0.92, green: 0.30, blue: 0.30)
        case .renamed, .copied: Color(red: 0.35, green: 0.55, blue: 0.98)
        case .conflicted: Color(red: 0.80, green: 0.30, blue: 0.85)
        }
    }

    static func letter(_ kind: ChangeKind) -> String {
        switch kind {
        case .added: "A"
        case .untracked: "U"
        case .modified: "M"
        case .typeChanged: "T"
        case .deleted: "D"
        case .renamed: "R"
        case .copied: "C"
        case .conflicted: "!"
        }
    }

    static func label(_ kind: ChangeKind) -> String {
        switch kind {
        case .added: "Eklendi"
        case .untracked: "Yeni"
        case .modified: "Değişti"
        case .typeChanged: "Türü değişti"
        case .deleted: "Silindi"
        case .renamed: "Yeniden adlandırıldı"
        case .copied: "Kopyalandı"
        case .conflicted: "Çakışma"
        }
    }
}

/// ↑2 ↓5 gibi küçük senkron rozeti.
struct SyncBadge: View {
    let ahead: Int
    let behind: Int

    var body: some View {
        HStack(spacing: 5) {
            if behind > 0 {
                Label("\(behind)", systemImage: "arrow.down")
                    .foregroundStyle(Theme.behind)
            }
            if ahead > 0 {
                Label("\(ahead)", systemImage: "arrow.up")
                    .foregroundStyle(Theme.ahead)
            }
        }
        .labelStyle(CompactLabel())
        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
    }
}

struct CompactLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 1) {
            configuration.icon.font(.system(size: 8.5, weight: .bold))
            configuration.title
        }
    }
}
