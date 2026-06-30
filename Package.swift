// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "MarkItDown",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MarkItDown", targets: ["MarkItDown"])
    ],
    targets: [
        .executableTarget(
            name: "MarkItDown",
            path: "Sources/MarkItDown"
        ),
        .testTarget(
            name: "MarkItDownTests",
            dependencies: ["MarkItDown"],
            path: "Tests/MarkItDownTests"
        )
    ]
)
