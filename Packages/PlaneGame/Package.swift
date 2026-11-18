// swift-tools-version: 6.2

import PackageDescription

// The paper plane game hidden in the empty Inbox (ADR-027): the world, its rules and the tap streak that opens it, as
// plain values with nothing to draw them. Foundation only, so its tests run on Linux; MailUI draws it.
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
    name: "PlaneGame",
    platforms: [.iOS("27.2")],
    products: [.library(name: "PlaneGame", targets: ["PlaneGame"])],
    targets: [
        .target(name: "PlaneGame", swiftSettings: strictSwift),
        .testTarget(name: "PlaneGameTests", dependencies: ["PlaneGame"], swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
