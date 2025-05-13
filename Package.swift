// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "whooshing.toolbox-server",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
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
        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-client-vapor", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-pgsql.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.10.0"),
    ],
    targets: [
        .target(
            name: "WhooshingServer",
            dependencies: [
                .product(name: "ErrorHandle", package: "whooshing.toolbox-basic"),
                .product(name: "DataConvertable", package: "whooshing.toolbox-basic"),
                .product(name: "Cryptos", package: "whooshing.toolbox-basic"),
                .product(name: "PgSQL", package: "whooshing.toolbox-pgsql"),
                .product(name: "WhooshingClient", package: "whooshing.toolbox-client-vapor"),
                .product(name: "Vapor", package: "whooshing-vapor"),
                .product(name: "Fluent", package: "whooshing-fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
            ],
            resources: [
                .process("Services/API/3.API请求流程.png")
            ]
        ),
        .testTarget(
            name: "toolbox-server-Tests",
            dependencies: [
                .product(name: "WhooshingClient", package: "whooshing.toolbox-client-vapor"),
                .target(name: "WhooshingServer")
            ]
        ),
    ]
)
