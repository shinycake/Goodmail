// swift-tools-version: 6.2

import PackageDescription

// Gmail's REST API and OAuth. No Gmail wire type leaves this module (ADR-005).
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
    name: "GmailProvider",
    platforms: [.iOS("27.2"), .watchOS("27.2")],
    products: [.library(name: "GmailProvider", targets: ["GmailProvider"])],
    dependencies: [.package(path: "../MailCore")],
    targets: [
        .target(name: "GmailProvider", dependencies: ["MailCore"], swiftSettings: strictSwift),
        .testTarget(
            name: "GmailProviderTests", dependencies: ["GmailProvider"], resources: [.copy("Fixtures")],
            swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
