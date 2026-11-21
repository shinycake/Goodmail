import Foundation
import MailCore
import Testing

/// A build's provisioning profile says which APNs server its device tokens belong to.
struct APNsEnvironmentTests {
    private func profile(_ value: String) -> String {
        """
        <plist version="1.0"><dict><key>Entitlements</key><dict>
        <key>aps-environment</key>
        \t\t<string>\(value)</string>
        <key>com.apple.developer.aps-environment</key>
        \t\t<string>\(value)</string>
        </dict></dict></plist>
        """
    }

    @Test func aDevelopmentProfileGetsSandboxTokens() {
        #expect(APNsEnvironment(provisioningProfile: profile("development")) == .sandbox)
    }

    @Test func aDistributionProfileGetsProductionTokens() {
        #expect(APNsEnvironment(provisioningProfile: profile("production")) == .production)
    }

    @Test func aBuildWithNoProfileGetsProductionTokens() {
        #expect(APNsEnvironment(provisioningProfile: nil) == .production, "as TestFlight and the App Store ship")
    }

    /// A Mac app keeps its profile in `Contents`, where an iPhone app's `embedded.mobileprovision` isn't. Missing it
    /// made a development Mac build register sandbox tokens as production ones, which APNs refuses.
    @Test(arguments: ["embedded.mobileprovision", "Contents/embedded.provisionprofile"])
    func aBundleIsReadWhereItsPlatformKeepsTheProfile(_ path: String) throws {
        let bundle = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).app")
        defer { try? FileManager.default.removeItem(at: bundle) }
        let file = bundle.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(profile("development").utf8).write(to: file)
        #expect(APNsEnvironment(bundleAt: bundle) == .sandbox)
    }
}
