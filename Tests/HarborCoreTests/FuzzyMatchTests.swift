import XCTest
@testable import HarborCore

final class FuzzyMatchTests: XCTestCase {
    func testScoreBasics() {
        XCTAssertEqual(FuzzyMatch.score("", "herhangi"), 0)
        XCTAssertNil(FuzzyMatch.score("xyz", "PulseBar"))
        XCTAssertNil(FuzzyMatch.score("rab", "bar"), "sıra önemli")
        XCTAssertNotNil(FuzzyMatch.score("pb", "PulseBar"))
        XCTAssertNotNil(FuzzyMatch.score("PULSE", "pulsebar"), "büyük/küçük harf duyarsız")
        XCTAssertNotNil(FuzzyMatch.score("İs", "islet"), "Türkçe büyük İ")
        XCTAssertNotNil(FuzzyMatch.score("çek", "Çek (pull)"))
    }

    func testRankingPrefersPrefixWordStartsAndContiguous() {
        let s = { FuzzyMatch.score($0, $1) ?? -1 }
        XCTAssertGreaterThan(s("pul", "PulseBar"), s("pul", "Upload Url"), "baştan eşleşme daha iyi")
        XCTAssertGreaterThan(s("gh", "Git Harbor"), s("gh", "nightly"), "kelime başları daha iyi")
        XCTAssertGreaterThan(s("bar", "PulseBar"), s("bar", "b_a_r"), "bitişik daha iyi")
    }

    func testRank() {
        let items = ["just-english-backend", "efehascanweb", "PulseBar", "Islet", "just-english-mobile"]
        XCTAssertEqual(FuzzyMatch.rank("jem", items, key: { $0 }), ["just-english-mobile"])
        XCTAssertEqual(FuzzyMatch.rank("je", items, key: { $0 }).prefix(2), ["just-english-mobile", "just-english-backend"],
                       "eşit puanda kısa önce")
        XCTAssertEqual(FuzzyMatch.rank("", items, key: { $0 }), items.sorted { $0.count < $1.count }.isEmpty ? [] : FuzzyMatch.rank("", items, key: { $0 }))
        XCTAssertEqual(FuzzyMatch.rank("", ["bb", "a", "cc"], key: { $0 }), ["a", "bb", "cc"])
        XCTAssertEqual(FuzzyMatch.rank("zz", items, key: { $0 }), [])
    }
}
