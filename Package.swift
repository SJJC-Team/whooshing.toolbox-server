// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

#warning("swift-system 最新版本尚不稳定，采用 exact: 1.6.5，稳定后应当回调")

let package = Package(
    name: "whooshing.toolbox-server",
    platforms: [
        .macOS(.v11),
        .iOS(.v14),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library( name: "WhooshingServer", targets: ["WhooshingServer"] )
    ],
    dependencies: [
        .package(url: "https://github.com/whooshing-workshop/whooshing-vapor.git", from: "1.1.2"),
        .package(url: "https://github.com/whooshing-workshop/whooshing-fluent.git", from: "1.0.3"),
        .package(url: "https://github.com/whooshing-workshop/whooshing.toolbox-basic.git", from: "1.5.6"),
        .package(url: "https://github.com/whooshing-workshop/whooshing.toolbox-client", from: "1.2.8"),
        .package(url: "https://github.com/whooshing-workshop/whooshing.toolbox-websocket.git", from: "1.1.5"),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.10.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-system", exact: "1.6.5"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.9.1")
    ],
    targets: [
        .target(
            name: "WhooshingServer",
            dependencies: [
                .product(name: "Vapor", package: "whooshing-vapor"),
                .product(name: "Fluent", package: "whooshing-fluent"),
                .product(name: "Cryptos", package: "whooshing.toolbox-basic"),
                .product(name: "ErrorHandle", package: "whooshing.toolbox-basic"),
                .product(name: "DataConvertable", package: "whooshing.toolbox-basic"),
                .product(name: "LoggingAdvanced", package: "whooshing.toolbox-basic"),
                .product(name: "WhooshingClient", package: "whooshing.toolbox-client"),
                .product(name: "WhooshingWebSocket", package: "whooshing.toolbox-websocket"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
                .product(name: "SystemPackage", package: "swift-system"),
                .product(name: "Logging", package: "swift-log")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "toolbox-server-Tests",
            dependencies: [
                .product(name: "WhooshingClient", package: "whooshing.toolbox-client"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .target(name: "WhooshingServer")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
    ]
)
