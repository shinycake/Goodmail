// swift-tools-version: 6.2

import PackageDescription

// Module boundaries are architecture (ADR-005): only MailStore imports GRDB, no Gmail wire type
// leaves GmailProvider, and nothing below MailUI imports UIKit.
let package = Package(
    name: "GoodmailKit",
    defaultLocalization: "en",
    platforms: [.iOS("27.2")],
    products: [
        .library(name: "MailCore", targets: ["MailCore"]),
        .library(name: "MailStore", targets: ["MailStore"]),
        .library(name: "GmailProvider", targets: ["GmailProvider"]),
        .library(name: "MailUI", targets: ["MailUI"]),
        .library(name: "MailIntents", targets: ["MailIntents"]),
    ],
    dependencies: [
        // The one approved third-party dependency (ADR-001).
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1")
    ],
    targets: [
        .target(name: "MailCore"),
        .target(
            name: "MailStore",
            dependencies: ["MailCore", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "GmailProvider", dependencies: ["MailCore"]),
        .target(
            name: "MailUI",
            dependencies: ["MailCore"],
            resources: [.process("Resources")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .target(name: "MailIntents", dependencies: ["MailCore"]),
        .testTarget(name: "MailCoreTests", dependencies: ["MailCore"]),
        .testTarget(name: "MailStoreTests", dependencies: ["MailStore"]),
        .testTarget(name: "MailUITests", dependencies: ["MailUI"]),
    ],
    swiftLanguageModes: [.v6]
)
