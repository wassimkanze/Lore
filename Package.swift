// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lore",
    platforms: [.macOS(.v15)],
    products: [.library(name: "LoreCore", targets: ["LoreCore"])],
    targets: [
        .target(name: "LoreCore", path: "Lore", exclude: ["App", "Features", "DesignSystem", "Resources"], sources: ["Core", "Integrations"]),
        .executableTarget(name: "LoreDiagnostics", dependencies: ["LoreCore"], path: "Scripts/Diagnostics"),
        .testTarget(name: "LoreTests", dependencies: ["LoreCore"], path: "LoreTests", resources: [.copy("Fixtures")])
    ]
)
