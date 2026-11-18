public import Foundation

/// Whether the relay can alert this device for an account, as its answers to the device's registrations say.
/// Changed only by `after(_:at:)`.
///
/// The relay keeps trying a login the mail server refused, and a server can refuse a good login once, so the reader
/// is told only once the refusals have lasted `AccountHealth.patience`. A password that is truly wrong fails the
/// device's own syncs too, which `AccountHealth` tells the reader of at once.
public enum AlertHealth: Equatable, Sendable {
    /// The relay took the last registration, or none has been refused.
    case working
    /// The mail server has refused the relay's login since `since`; not long enough yet to tell the reader.
    case refused(since: Date)
    /// The mail server has refused the relay's login for `AccountHealth.patience` or longer, so no alert comes.
    case paused

    /// The health after a registration at `date` ended with `outcome`. Only the mail server's refusal counts
    /// against the alerts: any other failure says nothing about the login.
    public func after(_ outcome: Result<Void, any Error>, at date: Date) -> AlertHealth {
        guard case .failure(let error) = outcome else { return .working }
        guard error as? PushRelayClient.Failure == .loginRefused else { return self }
        switch self {
        case .working: return .refused(since: date)
        case .refused(let since):
            return date.timeIntervalSince(since) >= AccountHealth.patience ? .paused : self
        case .paused: return .paused
        }
    }
}
