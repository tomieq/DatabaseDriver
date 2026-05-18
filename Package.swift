// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DatabaseDriver",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "DatabaseDriver",
            targets: ["DatabaseDriver"]
        ),
        .executable(name: "mysql-handshake", targets: ["mysql-handshake"])
    ],
    dependencies: [
        .package(url: "https://github.com/tomieq/SwiftExtensions", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.12.3"))
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "DatabaseDriver",
            dependencies: [
                .product(name: "SwiftExtensions", package: "SwiftExtensions"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .testTarget(
            name: "DatabaseDriverTests",
            dependencies: ["DatabaseDriver"]
        ),
        .executableTarget(
            name: "mysql-handshake",
            dependencies: ["DatabaseDriver"]
        )
    ]
)
