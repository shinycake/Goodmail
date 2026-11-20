// swift-tools-version: 6.2

import PackageDescription

// App Intents shared by the app, widgets and extensions (ADR-012).
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
    name: "MailIntents",
    platforms: [.iOS("27.2"), .macCatalyst("27.2")],
    products: [.library(name: "MailIntents", targets: ["MailIntents"])],
    dependencies: [.package(path: "../MailCore")],
    targets: [
        .target(name: "MailIntents", dependencies: ["MailCore"], swiftSettings: strictSwift),
        .testTarget(name: "MailIntentsTests", dependencies: ["MailIntents"], swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
