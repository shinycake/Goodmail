// swift-tools-version: 6.2

import PackageDescription

// Microsoft Graph's mail API and Microsoft sign-in. No Graph wire type leaves this module (ADR-005).
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
    name: "OutlookProvider",
    platforms: [.iOS("27.2"), .watchOS("27.2")],
    products: [.library(name: "OutlookProvider", targets: ["OutlookProvider"])],
    dependencies: [.package(path: "../MailCore")],
    targets: [
        .target(name: "OutlookProvider", dependencies: ["MailCore"], swiftSettings: strictSwift),
        .testTarget(
            name: "OutlookProviderTests", dependencies: ["OutlookProvider"], resources: [.copy("Fixtures")],
            swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
