// swift-tools-version: 6.2

import PackageDescription

// New-mail alerts: what the notification extension fetches and shows, and the actions and taps the app answers.
// Shared by the app and the extension, so it never imports UIKit or MailUI (ADR-005).
let package = Package(
    name: "MailNotifications",
    defaultLocalization: "en",
    platforms: [.iOS("27.2")],
    products: [.library(name: "MailNotifications", targets: ["MailNotifications"])],
    dependencies: [.package(path: "../MailCore"), .package(path: "../MailStore")],
    targets: [
        .target(
            name: "MailNotifications", dependencies: ["MailCore", "MailStore"], resources: [.process("Resources")]),
        .testTarget(name: "MailNotificationsTests", dependencies: ["MailNotifications"]),
    ],
    swiftLanguageModes: [.v6]
)
