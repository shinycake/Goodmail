/// The owner's choice, in the iPhone's Settings, whether the watch reads Gmail and Outlook itself (ADR-023). Carried
/// in the snapshot.
public enum WristIndependence: String, Codable, Sendable {
    case on
    case off

    /// Off until the iPhone's Settings offers the switch.
    public static let `default` = WristIndependence.off
}
