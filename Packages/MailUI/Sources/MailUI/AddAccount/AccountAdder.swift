import Foundation
public import MailCore
public import Observation

/// Adds an account: the reader picks a service, then signs in to it. The one place both the welcome screen and
/// Settings add accounts through, so each service's sign-in plugs in once, in the app's `signIn`.
@Observable
public final class AccountAdder {
    public enum State {
        /// Waiting for the reader to pick a service. `failure` is the last sign-in that failed, shown until the
        /// reader dismisses it; a cancelled sign-in isn't a failure.
        case choosing(failure: (any Error)?)
        /// Signing in to `service`; the other services wait.
        case signingIn(MailService)
    }

    public private(set) var state = State.choosing(failure: nil)
    /// The services offered, in order.
    public let services: [MailService]

    /// Runs after each account is added, set by whoever shows the adder.
    @ObservationIgnored public var onAdded: () -> Void = {}
    @ObservationIgnored private let signIn: (MailService) async throws -> Bool

    /// `signIn` signs in to a service and adds or refreshes its account, returning `false` if the reader cancelled.
    /// Each service's sign-in plugs in there.
    public init(
        services: [MailService] = MailService.allCases, signIn: @escaping (MailService) async throws -> Bool
    ) {
        self.services = services
        self.signIn = signIn
    }

    /// The service being signed in to, if one is.
    var signingIn: MailService? {
        if case .signingIn(let service) = state { service } else { nil }
    }

    /// The last sign-in that failed, for the alert.
    var failure: (any Error)? {
        if case .choosing(let failure) = state { failure } else { nil }
    }

    /// Signs in to `service`, unless a sign-in is already under way.
    public func add(_ service: MailService) async {
        guard case .choosing = state else { return }
        state = .signingIn(service)
        do {
            let added = try await signIn(service)
            state = .choosing(failure: nil)
            if added { onAdded() }
        } catch {
            state = .choosing(failure: error)
        }
    }

    /// The reader read the failure.
    func dismissFailure() {
        guard case .choosing(.some) = state else { return }
        state = .choosing(failure: nil)
    }
}

extension MailService {
    /// The service's name, as its own brand writes it, or for any other server what Mail calls it.
    var displayName: String {
        switch self {
        case .gmail: "Gmail"
        case .icloud: "iCloud"
        case .outlook: "Outlook"
        case .imap:
            String(
                localized: "Other Mail Account", table: "AddAccount", bundle: .module,
                comment: "The service chooser's choice for an account on any IMAP and SMTP server")
        }
    }
}
