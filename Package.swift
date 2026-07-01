// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ReviewReminder",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ReviewReminder",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/ReviewReminder",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-strict-concurrency=complete"]),
            ]
        ),
        .testTarget(
            name: "ReviewReminderTests",
            dependencies: ["ReviewReminder"],
            path: "Tests/ReviewReminderTests"
        ),
    ]
)
