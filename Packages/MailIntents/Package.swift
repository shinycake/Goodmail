// swift-tools-version: 6.2

import PackageDescription

// App Intents shared by the app, widgets and extensions (ADR-012).
let package = Package(
    name: "MailIntents",
    platforms: [.iOS("27.2")],
    products: [.library(name: "MailIntents", targets: ["MailIntents"])],
    dependencies: [.package(path: "../MailCore")],
    targets: [
        .target(name: "MailIntents", dependencies: ["MailCore"]),
        .testTarget(name: "MailIntentsTests", dependencies: ["MailIntents"]),
    ],
    swiftLanguageModes: [.v6]
)
