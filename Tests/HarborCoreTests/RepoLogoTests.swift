import XCTest
@testable import HarborCore

final class RepoLogoTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("logo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func touch(_ relative: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data([1]).write(to: url)
    }

    func testRank() {
        XCTAssertEqual(RepoLogo.rank("icon.png"), 0)
        XCTAssertEqual(RepoLogo.rank("Logo.SVG"), 2)
        XCTAssertEqual(RepoLogo.rank("favicon.ico"), 6)
        XCTAssertNil(RepoLogo.rank("icon.txt"))
        XCTAssertNil(RepoLogo.rank("screenshot.png"))
    }

    func testPrefersIconOverFavicon() throws {
        try touch("public/favicon.svg")
        try touch("assets/images/icon.png")
        XCTAssertEqual(RepoLogo.find(in: root.path), root.path + "/assets/images/icon.png")
    }

    func testSkipsNodeModulesAndHidden() throws {
        try touch("node_modules/pkg/icon.png")
        try touch(".hidden/icon.png")
        try touch("site/favicon.svg")
        XCTAssertEqual(RepoLogo.find(in: root.path), root.path + "/site/favicon.svg")
    }

    func testAppIconSetLargestPNG() throws {
        let set = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset")
        try FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
        try Data(count: 10).write(to: set.appendingPathComponent("16.png"))
        try Data(count: 500).write(to: set.appendingPathComponent("1024.png"))
        XCTAssertEqual(RepoLogo.find(in: root.path), set.path + "/1024.png")
    }

    func testNothingFound() throws {
        try touch("README.md")
        XCTAssertNil(RepoLogo.find(in: root.path))
    }
}
