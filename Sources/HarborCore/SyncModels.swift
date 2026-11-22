import Foundation

/// Otomatik senkron ayarları (UserDefaults'ta saklanır).
public struct SyncSettings: Codable, Hashable, Sendable {
    public var autoFetch: Bool
    /// Fetch aralığı (saniye).
    public var interval: TimeInterval
    /// Güvenliyse (temiz klasör, ileri sarılabilir) otomatik pull.
    public var autoPull: Bool
    /// Düşük güç modunda ya da pildeyken otomatik fetch'i ertele.
    public var pauseOnLowPower: Bool
    public init(autoFetch: Bool = true, interval: TimeInterval = 300, autoPull: Bool = true, pauseOnLowPower: Bool = true) {
        self.autoFetch = autoFetch
        self.interval = interval
        self.autoPull = autoPull
        self.pauseOnLowPower = pauseOnLowPower
    }
}

/// Depoda süren işlem (çakışma çözümü gerektirebilir).
public enum RepoOperation: String, Hashable, Sendable {
    case none, merge, rebase, cherryPick, revert
}

/// Fetch sonrası otomatik olarak ne yapılacağı.
public enum AutoPullDecision: Hashable, Sendable {
    /// Hiçbir şey (geride değil, ya da ayar kapalı).
    case nothing
    /// `git merge --ff-only @{u}`: güvenli ileri sarma.
    case fastForward
    /// Çekilecek değişiklik var ama otomatik çekmek güvenli değil; kullanıcıya göster.
    case needsAttention(reason: String)
}
