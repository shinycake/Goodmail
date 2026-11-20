// swift-tools-version: 6.2

import PackageDescription

// New-mail alerts: what the notification extension fetches and shows, and the actions and taps the app answers.
// Shared by the app and the extension, so it never imports UIKit or MailUI (ADR-005).
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
    name: "MailNotifications",
    defaultLocalization: "en",
    platforms: [.iOS("27.2"), .macCatalyst("27.2")],
    products: [.library(name: "MailNotifications", targets: ["MailNotifications"])],
    dependencies: [.package(path: "../MailCore"), .package(path: "../MailStore")],
    targets: [
        .target(
            name: "MailNotifications", dependencies: ["MailCore", "MailStore"], resources: [.process("Resources")],
            swiftSettings: strictSwift),
        .testTarget(name: "MailNotificationsTests", dependencies: ["MailNotifications"], swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
