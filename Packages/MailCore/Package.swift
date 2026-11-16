// swift-tools-version: 6.2

import PackageDescription

// The domain: models, the provider protocol, sync and compose logic. Foundation only (ADR-005).
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
    name: "MailCore",
    platforms: [.iOS("27.2")],
    products: [.library(name: "MailCore", targets: ["MailCore"])],
    targets: [
        .target(name: "MailCore", swiftSettings: strictSwift),
        .testTarget(name: "MailCoreTests", dependencies: ["MailCore"], swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
