// swift-tools-version: 6.2

import PackageDescription

// The domain: models, the provider protocol, sync and compose logic. Foundation only (ADR-005).
let package = Package(
    name: "MailCore",
    platforms: [.iOS("27.2")],
    products: [.library(name: "MailCore", targets: ["MailCore"])],
    targets: [
        .target(name: "MailCore"),
        .testTarget(name: "MailCoreTests", dependencies: ["MailCore"]),
    ],
    swiftLanguageModes: [.v6]
)
