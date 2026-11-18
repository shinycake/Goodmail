import Foundation

/// The relay's name for one alert (PushWorker/README.md). The iPhone's notification extension posts it back as the
/// alert arrives; an alert the iPhone doesn't confirm in time goes to the paired watch instead (ADR-023).
public enum AlertReceipt {
    static let key = "alert"

    /// The alert's ID in a push's payload, or `nil` when the push carries none, as from a relay older than the watch
    /// fallback.
    public static func id(in payload: [AnyHashable: Any]) -> String? {
        guard let value = payload[key] as? String, let id = UUID(uuidString: value) else { return nil }
        return id.uuidString.lowercased()
    }
}
