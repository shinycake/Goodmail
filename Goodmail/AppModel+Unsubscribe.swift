import Foundation
import MailCore

extension AppModel {
    /// Leaves mailing lists for the reader. One-click requests go over a session that keeps no cookies or
    /// credentials, as RFC 8058 asks.
    var listUnsubscriber: ListUnsubscriber {
        ListUnsubscriber(http: Self.unsubscribeSession, commands: commands)
    }

    private static let unsubscribeSession = URLSession(configuration: .ephemeral)
}
