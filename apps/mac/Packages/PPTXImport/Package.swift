// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PPTXImport",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PPTXImport", targets: ["PPTXImport"]),
    ],
    dependencies: [
        .package(path: "../PresenterCore"),
        .package(path: "../RenderEngine"),
    ],
    targets: [
        .target(
            name: "PPTXImport",
            dependencies: [
                "PresenterCore",
                "RenderEngine",
            ]
        ),
        .testTarget(name: "PPTXImportTests", dependencies: ["PPTXImport"]),
    ]
)
