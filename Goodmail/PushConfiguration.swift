import Foundation
import MailCore

/// Where this build's push relay is, and which APNs server its device tokens belong to.
enum PushConfiguration {
    /// The deployed PushWorker, from the `GOODMAIL_PUSH_RELAY_URL` build setting. `nil` leaves push off, as in
    /// builds made before the relay was deployed.
    static let relayURL: URL? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "GoodmailPushRelayURL") as? String,
            !value.isEmpty
        else { return nil }
        return URL(string: value)
    }()

    /// Development-signed builds carry a provisioning profile with `aps-environment` set to development, and get
    /// sandbox tokens. TestFlight and App Store builds carry no profile and get production ones.
    static let environment: APNsEnvironment = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
            let profile = try? String(contentsOf: url, encoding: .isoLatin1)
        else { return .production }
        let development = #/<key>aps-environment</key>\s*<string>development</string>/#
        return profile.contains(development) ? .sandbox : .production
    }()
}
