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

    /// Which APNs server this build's tokens belong to, from its provisioning profile.
    static let environment = APNsEnvironment(bundleAt: Bundle.main.bundleURL)
}
