// swift-tools-version: 6.2

import PackageDescription

// The reports iOS sends about how the app ran on this device (ADR-042): MetricKit's daily metrics and its crash, hang
// and exception diagnostics, read into plain values and kept in an archive of files. Foundation only, so its tests run
// on Linux; the part that reads MetricKit is fenced with `#if canImport(MetricKit)`. MailUI shows the archive and the
// app starts the feed.
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
    name: "FieldDiagnostics",
    platforms: [.iOS("27.2"), .macCatalyst("27.2")],
    products: [.library(name: "FieldDiagnostics", targets: ["FieldDiagnostics"])],
    targets: [
        .target(name: "FieldDiagnostics", swiftSettings: strictSwift),
        .testTarget(
            name: "FieldDiagnosticsTests", dependencies: ["FieldDiagnostics"], resources: [.copy("Fixtures")],
            swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
