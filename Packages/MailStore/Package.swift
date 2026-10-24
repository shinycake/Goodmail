// swift-tools-version: 6.2

import PackageDescription

// The local database. The only module that imports GRDB (ADR-001, ADR-005).
let package = Package(
    name: "MailStore",
    platforms: [.iOS("27.2")],
    products: [.library(name: "MailStore", targets: ["MailStore"])],
    dependencies: [
        .package(path: "../MailCore"),
        // The one approved third-party dependency (ADR-001).
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(name: "MailStore", dependencies: ["MailCore", .product(name: "GRDB", package: "GRDB.swift")]),
        .testTarget(name: "MailStoreTests", dependencies: ["MailStore"]),
    ],
    swiftLanguageModes: [.v6]
)
