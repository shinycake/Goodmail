// swift-tools-version: 6.2

import PackageDescription

// Mail accounts on IMAP and SMTP servers, iCloud Mail among them. No IMAP wire type leaves this module (ADR-005).
let package = Package(
    name: "IMAPProvider",
    platforms: [.iOS("27.2")],
    products: [.library(name: "IMAPProvider", targets: ["IMAPProvider"])],
    dependencies: [.package(path: "../MailCore")],
    targets: [
        .target(name: "IMAPProvider", dependencies: ["MailCore"]),
        .testTarget(name: "IMAPProviderTests", dependencies: ["IMAPProvider"]),
    ],
    swiftLanguageModes: [.v6]
)
