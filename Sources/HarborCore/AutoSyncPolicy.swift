import Foundation

/// Görev: otomatik senkron kararları (saf fonksiyonlar).
public enum AutoSyncPolicy {
    /// Fetch sonrası depo için otomatik pull kararı.
    public static func decide(status: RepoStatus, operation: RepoOperation, settings: SyncSettings) -> AutoPullDecision {
        // TODO(Qwen)
        .nothing
    }

    /// Bu depo şimdi fetch edilmeli mi.
    public static func shouldFetch(lastFetch: Date?, now: Date, settings: SyncSettings, lowPower: Bool) -> Bool {
        // TODO(Qwen)
        false
    }

    /// Aralık seçenekleri için okunur metin: 60 → "1 dk", 300 → "5 dk", 3600 → "1 sa", 5400 → "1 sa 30 dk", 30 → "30 sn".
    public static func intervalLabel(_ seconds: TimeInterval) -> String {
        // TODO(Qwen)
        ""
    }
}
