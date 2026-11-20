// swift-tools-version: 6.2

import PackageDescription

// The work behind the Apple Watch app (ADR-022, ADR-023): turning a mail database into the watch's snapshots, running
// its commands and building its conversations. The iPhone runs it for the watch; the watch will run it for the
// accounts it reads itself. Foundation only, so its tests run on Linux.
// Gmail and Outlook are the providers the watch reads itself.
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
    name: "MailWristHost",
    platforms: [.iOS("27.2"), .watchOS("27.2"), .macCatalyst("27.2")],
    products: [.library(name: "MailWristHost", targets: ["MailWristHost"])],
    dependencies: [
        .package(path: "../MailCore"), .package(path: "../MailStore"), .package(path: "../MailWrist"),
        .package(path: "../GmailProvider"), .package(path: "../OutlookProvider"),
    ],
    targets: [
        .target(
            name: "MailWristHost",
            dependencies: ["MailCore", "MailStore", "MailWrist", "GmailProvider", "OutlookProvider"],
            swiftSettings: strictSwift),
        .testTarget(name: "MailWristHostTests", dependencies: ["MailWristHost"], swiftSettings: strictSwift),
    ],
    swiftLanguageModes: [.v6]
)
