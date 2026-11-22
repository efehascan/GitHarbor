import Foundation

/// Görev: otomatik senkron kararları (saf fonksiyonlar).
public enum AutoSyncPolicy {
    /// Fetch sonrası depo için otomatik pull kararı.
    public static func decide(status: RepoStatus, operation: RepoOperation, settings: SyncSettings) -> AutoPullDecision {
        guard settings.autoPull else { return .nothing }
        guard status.branch != nil, status.upstream != nil else { return .nothing }
        guard status.behind > 0 else { return .nothing }
        if operation != .none {
            return .needsAttention(reason: "Süren bir işlem var")
        }
        if status.ahead > 0 {
            return .needsAttention(reason: "Dallar ayrıştı: önce birleştirme gerekli")
        }
        if status.changes.contains(where: { $0.kind != .untracked }) {
            return .needsAttention(reason: "Kaydedilmemiş değişiklikler var")
        }
        return .fastForward
    }

    /// Bu depo şimdi fetch edilmeli mi.
    public static func shouldFetch(lastFetch: Date?, now: Date, settings: SyncSettings, lowPower: Bool) -> Bool {
        guard settings.autoFetch else { return false }
        if lowPower, settings.pauseOnLowPower { return false }
        guard let lastFetch else { return true }
        return now.timeIntervalSince(lastFetch) >= settings.interval
    }

    /// Aralık seçenekleri için okunur metin: 60 → "1 dk", 300 → "5 dk", 3600 → "1 sa", 5400 → "1 sa 30 dk", 30 → "30 sn".
    public static func intervalLabel(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s) sn" }
        let m = s / 60
        if m < 60 { return "\(m) dk" }
        let sa = m / 60
        let dk = m % 60
        if dk == 0 { return "\(sa) sa" }
        return "\(sa) sa \(dk) dk"
    }
}
