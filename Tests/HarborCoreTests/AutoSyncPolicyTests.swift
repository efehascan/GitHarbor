import XCTest
@testable import HarborCore

final class AutoSyncPolicyTests: XCTestCase {
    private let on = SyncSettings()

    private func status(ahead: Int = 0, behind: Int = 0, upstream: String? = "origin/main", branch: String? = "main",
                        changes: [FileChange] = []) -> RepoStatus {
        RepoStatus(branch: branch, commit: "abc", upstream: upstream, ahead: ahead, behind: behind, changes: changes)
    }

    func testFastForwardOnlyWhenSafe() {
        XCTAssertEqual(AutoSyncPolicy.decide(status: status(behind: 3), operation: .none, settings: on), .fastForward)
        XCTAssertEqual(AutoSyncPolicy.decide(status: status(), operation: .none, settings: on), .nothing)
        XCTAssertEqual(AutoSyncPolicy.decide(status: status(ahead: 2), operation: .none, settings: on), .nothing)
    }

    func testUnsafeCasesNeedAttention() {
        XCTAssertEqual(AutoSyncPolicy.decide(status: status(ahead: 1, behind: 2), operation: .none, settings: on),
                       .needsAttention(reason: "Dallar ayrıştı: önce birleştirme gerekli"))
        XCTAssertEqual(AutoSyncPolicy.decide(status: status(behind: 2, changes: [FileChange(path: "a", kind: .modified, staged: false)]),
                                             operation: .none, settings: on),
                       .needsAttention(reason: "Kaydedilmemiş değişiklikler var"))
        XCTAssertEqual(AutoSyncPolicy.decide(status: status(behind: 2, changes: [FileChange(path: "n", kind: .untracked, staged: false)]),
                                             operation: .none, settings: on),
                       .fastForward, "izlenmeyen dosyalar ileri sarmayı engellemez")
        XCTAssertEqual(AutoSyncPolicy.decide(status: status(behind: 2), operation: .rebase, settings: on),
                       .needsAttention(reason: "Süren bir işlem var"))
    }

    func testOffOrNoUpstream() {
        var off = on
        off.autoPull = false
        XCTAssertEqual(AutoSyncPolicy.decide(status: status(behind: 2), operation: .none, settings: off), .nothing)
        XCTAssertEqual(AutoSyncPolicy.decide(status: status(behind: 2, upstream: nil), operation: .none, settings: on), .nothing)
        XCTAssertEqual(AutoSyncPolicy.decide(status: status(behind: 2, branch: nil), operation: .none, settings: on), .nothing)
    }

    func testShouldFetch() {
        let now = Date(timeIntervalSince1970: 10_000)
        XCTAssertTrue(AutoSyncPolicy.shouldFetch(lastFetch: nil, now: now, settings: on, lowPower: false))
        XCTAssertFalse(AutoSyncPolicy.shouldFetch(lastFetch: now.addingTimeInterval(-299), now: now, settings: on, lowPower: false))
        XCTAssertTrue(AutoSyncPolicy.shouldFetch(lastFetch: now.addingTimeInterval(-300), now: now, settings: on, lowPower: false))
        XCTAssertFalse(AutoSyncPolicy.shouldFetch(lastFetch: nil, now: now, settings: on, lowPower: true))
        var keep = on
        keep.pauseOnLowPower = false
        XCTAssertTrue(AutoSyncPolicy.shouldFetch(lastFetch: nil, now: now, settings: keep, lowPower: true))
        var off = on
        off.autoFetch = false
        XCTAssertFalse(AutoSyncPolicy.shouldFetch(lastFetch: nil, now: now, settings: off, lowPower: false))
    }

    func testIntervalLabel() {
        XCTAssertEqual(AutoSyncPolicy.intervalLabel(30), "30 sn")
        XCTAssertEqual(AutoSyncPolicy.intervalLabel(60), "1 dk")
        XCTAssertEqual(AutoSyncPolicy.intervalLabel(300), "5 dk")
        XCTAssertEqual(AutoSyncPolicy.intervalLabel(3600), "1 sa")
        XCTAssertEqual(AutoSyncPolicy.intervalLabel(5400), "1 sa 30 dk")
    }
}
