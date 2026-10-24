// swift-tools-version: 6.2

import PackageDescription

// Gmail's REST API and OAuth. No Gmail wire type leaves this module (ADR-005).
let package = Package(
    name: "GmailProvider",
    platforms: [.iOS("27.2")],
    products: [.library(name: "GmailProvider", targets: ["GmailProvider"])],
    dependencies: [.package(path: "../MailCore")],
    targets: [
        .target(name: "GmailProvider", dependencies: ["MailCore"]),
        .testTarget(name: "GmailProviderTests", dependencies: ["GmailProvider"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
