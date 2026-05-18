// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "DatabaseDriver",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "DatabaseDriver",
            targets: ["DatabaseDriver"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/tomieq/SwiftExtensions", from: "2.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "DatabaseDriver",
            dependencies: [
                .product(name: "SwiftExtensions", package: "SwiftExtensions")
            ]
        ),
        .testTarget(
            name: "DatabaseDriverTests",
            dependencies: ["DatabaseDriver"]
        )
    ]
)
