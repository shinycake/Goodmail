// swift-tools-version: 6.2

import PackageDescription

// Microsoft Graph's mail API and Microsoft sign-in. No Graph wire type leaves this module (ADR-005).
let package = Package(
    name: "OutlookProvider",
    platforms: [.iOS("27.2")],
    products: [.library(name: "OutlookProvider", targets: ["OutlookProvider"])],
    dependencies: [.package(path: "../MailCore")],
    targets: [
        .target(name: "OutlookProvider", dependencies: ["MailCore"]),
        .testTarget(name: "OutlookProviderTests", dependencies: ["OutlookProvider"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
