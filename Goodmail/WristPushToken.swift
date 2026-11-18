import Foundation
import MailCore

/// The paired watch's APNs token, which the iPhone registers with the relay beside its own (ADR-023). Kept, so a
/// relaunch registers it again before the watch says anything.
extension AppModel {
    private nonisolated static let watchPushTokenKey = "WristPushToken"

    /// The watch token the watch sent last, or `nil` when no paired watch has the app.
    static var watchPushToken: String? {
        UserDefaults.standard.string(forKey: watchPushTokenKey)
    }

    /// Registers `token` beside this iPhone's own, or takes the watch off the relay when it is `nil`. Nothing to do
    /// when the watch said the same thing before.
    func pairWatch(_ token: String?) async {
        guard token != Self.watchPushToken else { return }
        UserDefaults.standard.set(token, forKey: Self.watchPushTokenKey)
        pushDevice = pushDevice?.pairing(token)
        await refreshPush()
    }
}
