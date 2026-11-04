// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PresenterCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PresenterCore", targets: ["PresenterCore"]),
        .executable(name: "library-bench", targets: ["library-bench"]),
    ],
    dependencies: [
        .package(path: "../automerge-swift"),
        .package(url: "https://github.com/apple/swift-collections.git", from: "1.1.0")
    ],
    targets: [
        .target(
            name: "PresenterCore",
            dependencies: [
                .product(name: "Automerge", package: "automerge-swift"),
                .product(name: "Collections", package: "swift-collections")
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "library-bench",
            dependencies: ["PresenterCore"]
        ),
        .testTarget(name: "PresenterCoreTests", dependencies: ["PresenterCore"]),
    ]
)
