// swift-tools-version: 6.2

import PackageDescription

// The Apple Watch app's model (ADR-022): the snapshot of the Inbox the iPhone sends the watch, the channel that
// carries it, and the watch's view models. Foundation and Observation, so its tests run on Linux; WatchConnectivity
// is fenced with `#if canImport`.
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
    name: "MailWrist",
    platforms: [.iOS("27.2"), .watchOS("27.2")],
    products: [.library(name: "MailWrist", targets: ["MailWrist"])],
    dependencies: [.package(path: "../MailCore")],
    targets: [
        .target(name: "MailWrist", dependencies: ["MailCore"], swiftSettings: strictSwift),
        .testTarget(name: "MailWristTests", dependencies: ["MailWrist"], swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
