import XCTest
@testable import HarborCore

/// Uçtan uca: deneme ortamını (scripts/make-fixtures.sh) kurar, HarborStore'u başlatır;
/// otomatik fetch/ileri sarma, uyarı, çakışma tespiti, bildirim olayları, değişiklikler ve geçmiş oturumları.
@MainActor
final class EndToEndTests: XCTestCase {
    private var base = ""

    override func setUp() async throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("harbor-e2e-" + UUID().uuidString).path
        let script = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("scripts/make-fixtures.sh").path
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script, base]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "deneme ortamı kurulamadı")
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(atPath: base)
    }

    /// Koşul sağlanana kadar bekler (sabit gecikme değil; en çok `timeout`).
    private func waitUntil(_ timeout: TimeInterval = 30, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return condition()
    }

    func testAutoSyncAttentionConflictAndEvents() async throws {
        let store = HarborStore(fileURL: URL(fileURLWithPath: base + "/workspace.json"))
        store.updateSettings { $0 = SyncSettings() }
        var events: [SyncEvent] = []
        store.onEvent = { events.append($0) }
        XCTAssertEqual(store.workspace.repos.count, 5)
        XCTAssertEqual(store.workspace.folders.map(\.name), ["Ürün", "Sorunlu"])
        store.start()

        func id(_ name: String) -> UUID { store.workspace.repos.first { $0.name == name }!.id }
        let geride = id("Geride"), kirli = id("Kirli"), catisma = id("Catisma"), yeni = id("Yeni-dal"), liman = id("Liman")

        let synced = await waitUntil {
            store.statuses[geride]?.behind == 0 && store.sync[geride]?.lastFetch != nil
                && store.sync[kirli]?.attention != nil
        }
        XCTAssertTrue(synced, "otomatik senkron tamamlanmadı: \(String(describing: store.sync))")
        XCTAssertTrue(FileManager.default.fileExists(atPath: base + "/repos/Geride/remote.txt"), "Geride ileri sarılmalı")
        XCTAssertEqual(store.sync[kirli]?.attention, "Kaydedilmemiş değişiklikler var")
        XCTAssertEqual(store.statuses[kirli]?.behind, 1)
        XCTAssertTrue(events.contains(.pulled(repo: "Geride", commits: 2, branch: "main")), "\(events)")
        XCTAssertTrue(events.contains(.attention(repo: "Kirli", reason: "Kaydedilmemiş değişiklikler var")), "\(events)")

        await store.refreshOperation(catisma)
        XCTAssertEqual(store.sync[catisma]?.operation, .merge)
        XCTAssertNil(store.statuses[yeni]?.upstream)
        XCTAssertEqual(store.statuses[liman]?.changes.count ?? 0 >= 4, true)

        // Yayınla: Yeni-dal'ın dalı uzağa gider ve upstream kurulur.
        await store.push(yeni)
        let published = await waitUntil { store.statuses[yeni]?.upstream == "origin/deneme/yayin" }
        XCTAssertTrue(published)
        XCTAssertNil(store.syncAlert)
    }

    func testChangesAndHistorySessionsOnRichRepo() async throws {
        let store = HarborStore(fileURL: URL(fileURLWithPath: base + "/workspace.json"))
        let repo = store.workspace.repos.first { $0.name == "Liman" }!
        let status = try await Git.status(in: repo.path)
        let changes = ChangesSession(repo: repo, onChange: {})
        changes.update(status: status, operation: .none)
        XCTAssertEqual(Set(status.changes.map(\.kind)), [.modified, .renamed, .untracked])

        // Yeniden adlandırma: fark yeni dosya değil, yeniden adlandırma olarak gelir (içerik aynı → parça yok).
        let rename = try XCTUnwrap(status.changes.first { $0.kind == .renamed })
        let renameDiff = try await Git.diff(path: rename.path, oldPath: rename.oldPath, staged: true, untracked: false, in: repo.path)
        XCTAssertEqual(renameDiff?.oldPath, "README.md")
        XCTAssertEqual(renameDiff?.newPath, "BENIOKU.md")
        XCTAssertEqual(renameDiff?.isNewFile, false)
        XCTAssertEqual(renameDiff?.hunks, [])

        // app.swift: yalnızca "let e = 5" satırını sahneye ekle
        changes.select(status.changes.first { $0.path == "app.swift" && !$0.staged })
        let loaded = await waitUntil { changes.diff != nil }
        XCTAssertTrue(loaded)
        let diff = try XCTUnwrap(changes.diff)
        let ref = try XCTUnwrap(diff.hunks.enumerated().lazy.compactMap { h, hunk in
            hunk.lines.firstIndex { $0.kind == .added && $0.text == "let e = 5" }.map { DiffLineRef(hunk: h, line: $0) }
        }.first)
        changes.toggleLine(ref, extend: false)
        await changes.applySelectionToIndex()
        XCTAssertNil(changes.lastError)
        let index = String(decoding: try Git.runSync(["show", ":app.swift"], in: repo.path), as: UTF8.self)
        XCTAssertTrue(index.contains("let e = 5"))
        XCTAssertTrue(index.contains("let b = 20"), "seçilmeyen b=25 değişikliği sahnede olmamalı")

        // Commit
        changes.update(status: try await Git.status(in: repo.path), operation: .none)
        changes.summary = "Seçili satır commit'i"
        XCTAssertTrue(changes.canCommit)
        await changes.commit()
        XCTAssertNil(changes.lastError)
        XCTAssertEqual(changes.summary, "")

        // Stash listesi
        await changes.loadStashes()
        XCTAssertEqual(changes.stashes.count, 1)
        XCTAssertTrue(changes.stashes[0].message.contains("yarım kalan notlar"))

        // Geçmiş: son commit en üstte, etiket ve dallar
        let history = HistorySession(repo: repo, onChange: {})
        await history.reload(force: true)
        XCTAssertEqual(history.commits.first?.subject, "Seçili satır commit'i")
        XCTAssertEqual(history.tags.map(\.name), ["v1.0"])
        XCTAssertEqual(Set(history.localBranches.map(\.name)), ["main", "ozellik/arama"])
        XCTAssertEqual(history.gitHubRepo, nil, "yerel uzak GitHub değil")
        let feature = try XCTUnwrap(history.localBranches.first { $0.name == "ozellik/arama" })
        XCTAssertEqual(feature.upstream, "origin/ozellik/arama")
        await history.select(history.commits.first { $0.subject.contains("#12") })
        XCTAssertEqual(history.files.first?.newPath, "util.swift")
        XCTAssertEqual(GitHubParsing.issueNumbers(in: history.message), [12])
    }
}
