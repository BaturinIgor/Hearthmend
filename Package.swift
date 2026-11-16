// swift-tools-version:5.9
import PackageDescription

// Ядро игры без UIKit: правила поля, энергия, заказы. Собирается и тестируется на Linux (CI) и подключается
// к приложению как локальный пакет (project.yml).
let package = Package(
    name: "HearthCore",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "HearthCore", targets: ["HearthCore"])
    ],
    targets: [
        .target(
            name: "HearthCore",
            path: "Sources/HearthCore",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "HearthCoreTests",
            dependencies: ["HearthCore"],
            path: "Tests/HearthCoreTests"
        )
    ]
)
