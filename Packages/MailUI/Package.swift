// swift-tools-version: 6.2

import PackageDescription

// The UIKit screens and their view models. The only module that imports UIKit (ADR-005).
let package = Package(
    name: "MailUI",
    defaultLocalization: "en",
    platforms: [.iOS("27.2")],
    products: [.library(name: "MailUI", targets: ["MailUI"])],
    dependencies: [.package(path: "../MailCore")],
    targets: [
        .target(
            name: "MailUI",
            dependencies: ["MailCore"],
            resources: [.process("Resources")],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(name: "MailUITests", dependencies: ["MailUI"]),
    ],
    swiftLanguageModes: [.v6]
)
