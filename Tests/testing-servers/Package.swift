// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "inline-testing",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .watchOS(.v6),
        .tvOS(.v13),
    ],
    dependencies: [
        // 💧 Vapor -- Swift 服务器端第三方框架
        .package(url: "https://github.com/SJJC-Team/whooshing-vapor.git", .upToNextMajor(from: "1.0.7")),
        // ⭐️ Whooshing 系统基本框架
        .package(url: "https://github.com/SJJC-Team/whooshing.toolbox-basic.git", .upToNextMajor(from: "1.4.3")),
        // 🔵 Swift 高性能网络通讯模块
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.65.0"),
        // 🗄 关系型和非关系型数据库的 ORM(对象关系映射)
        .package(url: "https://github.com/SJJC-Team/whooshing-fluent.git", from: "1.0.0"),
        // 🐘 对 PostgreSQL 的 Fluent 驱动器
        .package(url: "https://github.com/vapor/fluent-postgres-driver.git", from: "2.8.0"),
        
        .package(path: "../../../whooshing.toolbox-server"),
    ],
    targets: [
        .executableTarget(
            name: "App",
            dependencies: [
                .product(name: "Vapor", package: "whooshing-vapor"),
                .product(name: "ErrorHandle", package: "whooshing.toolbox-basic"),
                .product(name: "DataConvertable", package: "whooshing.toolbox-basic"),
                .product(name: "NIOAdvanced", package: "whooshing.toolbox-basic"),
                .product(name: "Cryptos", package: "whooshing.toolbox-basic"),
                .product(name: "WhooshingServer", package: "whooshing.toolbox-server"),
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "Fluent", package: "whooshing-fluent"),
                .product(name: "FluentPostgresDriver", package: "fluent-postgres-driver"),
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)

var swiftSettings: [SwiftSetting] { [
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableExperimentalFeature("StrictConcurrency"),
] }
