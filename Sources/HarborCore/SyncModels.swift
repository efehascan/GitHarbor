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
    /// Otomatik çekilen ya da dikkat isteyen depolar için bildirim.
    public var notify: Bool
    public init(autoFetch: Bool = true, interval: TimeInterval = 300, autoPull: Bool = true, pauseOnLowPower: Bool = true,
                notify: Bool = true) {
        self.autoFetch = autoFetch
        self.interval = interval
        self.autoPull = autoPull
        self.pauseOnLowPower = pauseOnLowPower
        self.notify = notify
    }

    enum CodingKeys: String, CodingKey { case autoFetch, interval, autoPull, pauseOnLowPower, notify }

    /// Eski kayıtta olmayan alanlar varsayılan değerini alır.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoFetch = try c.decodeIfPresent(Bool.self, forKey: .autoFetch) ?? true
        interval = try c.decodeIfPresent(TimeInterval.self, forKey: .interval) ?? 300
        autoPull = try c.decodeIfPresent(Bool.self, forKey: .autoPull) ?? true
        pauseOnLowPower = try c.decodeIfPresent(Bool.self, forKey: .pauseOnLowPower) ?? true
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? true
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

/// Bildirim gerektiren senkron olayları.
public enum SyncEvent: Hashable, Sendable {
    /// Otomatik ileri sarıldı: kaç commit geldi.
    case pulled(repo: String, commits: Int, branch: String)
    /// Çekilecek değişiklik var ama otomatik çekilemedi.
    case attention(repo: String, reason: String)
}
