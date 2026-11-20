// swift-tools-version: 6.2

import PackageDescription

// Mail accounts on IMAP and SMTP servers, iCloud Mail among them. No IMAP wire type leaves this module (ADR-005).
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
    name: "IMAPProvider",
    platforms: [.iOS("27.2"), .macCatalyst("27.2")],
    products: [.library(name: "IMAPProvider", targets: ["IMAPProvider"])],
    dependencies: [.package(path: "../MailCore")],
    targets: [
        .target(name: "IMAPProvider", dependencies: ["MailCore"], swiftSettings: strictSwift),
        .testTarget(name: "IMAPProviderTests", dependencies: ["IMAPProvider"], swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
