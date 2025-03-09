// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "file-changes",
    platforms: [
      .macOS(.v13)
    ],
    products: [
        .library(
                name: "FileChangeStream",
                targets: ["FileChangeStream"]),
        .executable(name: "Example",
                    targets: ["Example"]
        )
    ],
    dependencies: [
    ],
    targets: [
        .target(
                name: "FileChangeStream",
                path: "Sources/FileChangeStream"
        ),
        .executableTarget(
                name: "Example",
                dependencies: ["FileChangeStream"]),
    ]
)
