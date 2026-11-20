// swift-tools-version: 6.2

import PackageDescription

// Builds each account's mail client from the sign-in the device keeps, one way for the app and every extension that
// reaches the services itself.
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
    name: "MailClients",
    platforms: [.iOS("27.2")],
    products: [.library(name: "MailClients", targets: ["MailClients"])],
    dependencies: [
        .package(path: "../MailCore"), .package(path: "../GmailProvider"), .package(path: "../OutlookProvider"),
        .package(path: "../IMAPProvider"),
    ],
    targets: [
        .target(
            name: "MailClients", dependencies: ["MailCore", "GmailProvider", "OutlookProvider", "IMAPProvider"],
            swiftSettings: strictSwift)
    ],
    swiftLanguageModes: [.v6]
)
