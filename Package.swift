// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GitHarbor",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "GitHarbor", targets: ["GitHarbor"])],
    targets: [
        .target(name: "HarborCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "GitHarbor", dependencies: ["HarborCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "HarborCoreTests", dependencies: ["HarborCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
