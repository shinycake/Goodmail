public import Foundation

/// How an account's syncs are going, as far as the reader needs to know. Changed only by `after(_:at:)`.
///
/// A sign-in the service turned down needs the reader at once, since signing in again is the only fix. Anything else
/// usually passes by itself, so it is shown only once it has lasted `patience`. Being offline or cancelled says
/// nothing about the account and changes nothing.
public enum AccountHealth: Equatable, Sendable {
    /// The last sync worked, or none has failed yet.
    case healthy
    /// Syncs have failed since `since`, the latest for `reason`; not long enough yet to tell the reader.
    case faltering(FailureReason, since: Date)
    /// Syncs have failed for `patience` or longer, the latest for `reason`.
    case failing(FailureReason)
    /// The service turned down the account's stored sign-in, as when a token is revoked or a password changed.
    /// Only a sync that works clears it, as after signing in again.
    case needsSignIn

    /// How long failures go on before the reader is told of them.
    public static let patience: TimeInterval = 10 * 60

    /// The health after a sync at `date` ended with `outcome`.
    public func after(_ outcome: Result<Void, any Error>, at date: Date) -> AccountHealth {
        guard case .failure(let error) = outcome else { return .healthy }
        if error is CancellationError { return self }
        if let error = error as? any SignInRejecting, error.rejectsSignIn { return .needsSignIn }
        let reason = FailureReason(error)
        if reason == .offline { return self }
        switch self {
        case .healthy: return .faltering(reason, since: date)
        case .faltering(_, let since):
            return date.timeIntervalSince(since) >= Self.patience ? .failing(reason) : .faltering(reason, since: since)
        case .failing: return .failing(reason)
        case .needsSignIn: return .needsSignIn
        }
    }

    /// What the reader is told, or `nil` while there is nothing to tell.
    public var problem: AccountProblem? {
        switch self {
        case .healthy, .faltering: nil
        case .failing(let reason): .cantSync(reason)
        case .needsSignIn: .signInRejected
        }
    }
}

/// An account's problem that the reader is told of.
public enum AccountProblem: Equatable, Sendable {
    /// The service turned down the stored sign-in; signing in again fixes it.
    case signInRejected
    /// Syncs have failed for a while, the latest for this reason.
    case cantSync(FailureReason)
    /// The mail syncs, but its server has kept refusing the relay's login, so new mail doesn't alert (`AlertHealth`).
    case alertsPaused
}

/// An error that can say the service turned down the account's stored sign-in: a revoked token, a changed password.
/// Providers conform their errors, so health can tell a sign-in to renew from a server having a bad moment.
public protocol SignInRejecting: Error {
    var rejectsSignIn: Bool { get }
}

extension OAuthSession.Failure: SignInRejecting {
    /// No refresh token is stored, as after the Keychain was reset.
    public var rejectsSignIn: Bool { self == .signedOut }
}

extension OAuthClient.Failure: SignInRejecting {
    /// The service no longer honors the refresh token (RFC 6749 §5.2), or wants the person to sign in themselves, as
    /// Microsoft says after a password change or a new sign-in policy.
    public var rejectsSignIn: Bool {
        guard case .tokenEndpoint(_, let error?) = self else { return false }
        return error == "invalid_grant" || error == "interaction_required"
    }
}
