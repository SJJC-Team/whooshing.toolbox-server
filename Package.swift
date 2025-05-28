// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "whooshing.toolbox-server",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v14),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    products: [
        .library( name: "WhooshingServer", targets: ["WhooshingServer"] )
    ],
    dependencies: [
        .package(url: "https://github.com/SJJC-Team/whooshing-vapor.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/SJJC-Team/whooshing-fluent.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-basic.git", .upToNextMajor(from: "1.2.3")),
        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-client", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-websocket.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-pgsql.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.10.0"),
        .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "WhooshingServer",
            dependencies: [
                .product(name: "Vapor", package: "whooshing-vapor"),
                .product(name: "Fluent", package: "whooshing-fluent"),
                .product(name: "Cryptos", package: "whooshing.toolbox-basic"),
                .product(name: "PgSQL", package: "whooshing.toolbox-pgsql"),
                .product(name: "ErrorHandle", package: "whooshing.toolbox-basic"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "DataConvertable", package: "whooshing.toolbox-basic"),
                .product(name: "WhooshingClient", package: "whooshing.toolbox-client"),
                .product(name: "WhooshingWebSocket", package: "whooshing.toolbox-websocket"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver")
            ]
        ),
        .testTarget(
            name: "toolbox-server-Tests",
            dependencies: [
                .product(name: "WhooshingClient", package: "whooshing.toolbox-client"),
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .target(name: "WhooshingServer")
            ]
        ),
    ]
)
