import HarborCore
import UserNotifications

/// Senkron olaylarını macOS bildirimi olarak gösterir. İzin ilk olayda istenir.
@MainActor
enum Notifier {
    private static var asked = false

    static func post(_ event: SyncEvent) {
        // Paketlenmemiş çalıştırmada (swift run, testler) bildirim merkezi uygulamayı düşürür.
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        if !asked {
            asked = true
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
        let content = UNMutableNotificationContent()
        switch event {
        case .pulled(let repo, let commits, let branch):
            content.title = repo
            content.body = "\(commits) yeni commit \(branch) dalına çekildi"
        case .attention(let repo, let reason):
            content.title = "\(repo): çekilecek değişiklik var"
            content.body = reason
        }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
