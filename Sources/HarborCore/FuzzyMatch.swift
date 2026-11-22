import Foundation

/// Komut paleti için bulanık eşleştirme (kurallar haritada: "Komut paleti (FuzzyMatch)").
public enum FuzzyMatch {
    private static let tr = Locale(identifier: "tr")
    private static let separators: Set<Character> = [" ", "-", "_", "/", "."]

    /// `query` karakterleri `candidate` içinde sırayla geçiyorsa puan, geçmiyorsa nil. Büyük puan daha iyi.
    /// Boş sorgu her şeyle 0 puanla eşleşir.
    public static func score(_ query: String, _ candidate: String) -> Int? {
        let q = Array(query.lowercased(with: tr))
        guard !q.isEmpty else { return 0 }
        let orig = Array(candidate)
        let c = Array(candidate.lowercased(with: tr))
        var j = 0, last = -1, total = 0
        for ch in q {
            guard let i = (j..<c.count).first(where: { c[$0] == ch }) else { return nil }
            total += 1
            if i == 0 {
                total += 8
            } else if separators.contains(c[i - 1])
                        || (orig.count == c.count && orig[i - 1].isLowercase && orig[i].isUppercase) {
                total += 5
            }
            if last >= 0 {
                if i == last + 1 { total += 6 }
                total -= i - last - 1
            }
            last = i
            j = i + 1
        }
        return total
    }

    /// Adayları puana göre sıralar (eşit puanda kısa aday önce, sonra özgün sıra); eşleşmeyenler atılır.
    public static func rank<T>(_ query: String, _ items: [T], key: (T) -> String) -> [T] {
        items.enumerated()
            .compactMap { i, item -> (score: Int, length: Int, index: Int, item: T)? in
                let k = key(item)
                return score(query, k).map { ($0, k.count, i, item) }
            }
            .sorted { a, b in
                if a.score != b.score { return a.score > b.score }
                if a.length != b.length { return a.length < b.length }
                return a.index < b.index
            }
            .map(\.item)
    }
}
