/// The owner's choice, in the iPhone's Settings, whether the watch reads Gmail and Outlook itself (ADR-023). Carried
/// in the snapshot.
public enum WristIndependence: String, Codable, Sendable {
    case on
    case off

    /// On, unless the owner turns "Mail Without iPhone" off in the iPhone's Settings.
    public static let `default` = WristIndependence.on

    /// The switch's position.
    public init(mailWithoutIPhone: Bool) {
        self = mailWithoutIPhone ? .on : .off
    }
}
