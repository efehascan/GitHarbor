import Foundation

/// Görev: komut paleti için bulanık eşleştirme.
public enum FuzzyMatch {
    /// `query` karakterleri `candidate` içinde sırayla geçiyorsa puan, geçmiyorsa nil. Büyük puan daha iyi.
    /// Boş sorgu her şeyle 0 puanla eşleşir.
    public static func score(_ query: String, _ candidate: String) -> Int? {
        // TODO(Qwen)
        nil
    }

    /// Adayları puana göre sıralar (eşit puanda kısa aday önce, sonra özgün sıra); eşleşmeyenler atılır.
    public static func rank<T>(_ query: String, _ items: [T], key: (T) -> String) -> [T] {
        // TODO(Qwen)
        []
    }
}
