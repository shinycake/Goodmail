// swift-tools-version: 6.2

import PackageDescription

// iCloud Mail over IMAP and SMTP with an app-specific password. No IMAP wire type leaves this module (ADR-005).
let package = Package(
    name: "ICloudProvider",
    platforms: [.iOS("27.2")],
    products: [.library(name: "ICloudProvider", targets: ["ICloudProvider"])],
    dependencies: [.package(path: "../MailCore")],
    targets: [
        .target(name: "ICloudProvider", dependencies: ["MailCore"]),
        .testTarget(name: "ICloudProviderTests", dependencies: ["ICloudProvider"]),
    ],
    swiftLanguageModes: [.v6]
)
