// swift-tools-version: 6.2

import PackageDescription

// The local database. The only module that imports GRDB (ADR-001, ADR-005).
// The strictest Swift the toolchain offers, the same in every manifest and the app targets (ADR-021). scripts/check
// fails when this list drifts from scripts/strict-swift.
let strictSwift: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("ImmutableWeakCaptures"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InternalImportsByDefault"),
    .enableUpcomingFeature("MemberImportVisibility"),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableExperimentalFeature("Lifetimes"),
    .strictMemorySafety(),
    .treatAllWarnings(as: .error),
]

let package = Package(
    name: "MailStore",
    platforms: [.iOS("27.2"), .watchOS("27.2"), .macCatalyst("27.2")],
    products: [.library(name: "MailStore", targets: ["MailStore"])],
    dependencies: [
        .package(path: "../MailCore"),
        // The one approved third-party dependency (ADR-001).
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1"),
    ],
    targets: [
        .target(
            name: "MailStore", dependencies: ["MailCore", .product(name: "GRDB", package: "GRDB.swift")],
            swiftSettings: strictSwift),
        .testTarget(name: "MailStoreTests", dependencies: ["MailStore"], swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
