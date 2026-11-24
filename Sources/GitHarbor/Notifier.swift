import AppKit
import HarborCore
import UserNotifications

/// Senkron olaylarını macOS bildirimi olarak gösterir. İzin ilk olayda istenir.
@MainActor
enum Notifier {
    private static var asked = false

    /// Ayarlardaki "Deneme bildirimi".
    static func test() {
        let logo = RepoLogos.png(NSApp.applicationIconImage, side: 128)
            .flatMap { data -> URL? in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("githarbor-test-logo.png")
                return (try? data.write(to: url)) != nil ? url : nil
            }
        post(.pulled(repo: "Git Harbor Desktop", commits: 1, branch: "main"), logo: logo)
    }

    /// `logo`: depo logosunun PNG'si (varsa bildirimde görünür).
    static func post(_ event: SyncEvent, logo: URL? = nil) {
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
        if let logo {
            // Ek, dosyayı bildirim deposuna taşır; önbellekteki asıl dosya kalsın diye kopyası verilir.
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
            if (try? FileManager.default.copyItem(at: logo, to: copy)) != nil,
               let attachment = try? UNNotificationAttachment(identifier: "logo", url: copy) {
                content.attachments = [attachment]
            }
        }
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
