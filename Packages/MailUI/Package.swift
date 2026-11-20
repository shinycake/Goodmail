// swift-tools-version: 6.2

import PackageDescription

// The UIKit screens and their view models. The only module that imports UIKit (ADR-005).
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
    name: "MailUI",
    defaultLocalization: "en",
    platforms: [.iOS("27.2"), .macCatalyst("27.2")],
    products: [.library(name: "MailUI", targets: ["MailUI"])],
    dependencies: [.package(path: "../MailCore"), .package(path: "../PlaneGame")],
    targets: [
        .target(
            name: "MailUI",
            dependencies: ["MailCore", "PlaneGame"],
            resources: [.process("Resources")],
            swiftSettings: strictSwift + [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "MailUITests", dependencies: ["MailUI", "PlaneGame"], swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
