// swift-tools-version: 6.2

import PackageDescription

// The Apple Watch app's screens (ADR-022), in SwiftUI. It builds for iOS too, so the Linux build type-checks it;
// the few watch-only APIs are fenced where they are used.
//
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
    name: "MailWristUI",
    defaultLocalization: "en",
    platforms: [.iOS("27.2"), .watchOS("27.2")],
    products: [.library(name: "MailWristUI", targets: ["MailWristUI"])],
    dependencies: [.package(path: "../MailCore"), .package(path: "../MailWrist")],
    targets: [
        .target(
            name: "MailWristUI",
            dependencies: ["MailCore", "MailWrist"],
            resources: [.process("Resources")],
            swiftSettings: strictSwift + [.defaultIsolation(MainActor.self)]
        )
    ],
    swiftLanguageModes: [.v6]
)
