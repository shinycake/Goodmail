import Foundation
import MailCore
import Observation

/// Adds an account: the reader picks a service, then signs in to it. The one place both the welcome screen and
/// Settings add accounts through, so each service's sign-in plugs in once, in the app's `signIn`.
@Observable
public final class AccountAdder {
    public enum State: Equatable {
        /// Waiting for the reader to pick a service.
        case choosing
        /// Signing in to `service`; the other services wait.
        case signingIn(MailService)
    }

    public private(set) var state = State.choosing
    /// The last sign-in that failed, for the view to show. A cancelled sign-in isn't a failure.
    public var error: (any Error)?
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

    /// Signs in to `service`, unless a sign-in is already under way.
    public func add(_ service: MailService) async {
        guard state == .choosing else { return }
        state = .signingIn(service)
        defer { state = .choosing }
        do {
            if try await signIn(service) { onAdded() }
        } catch {
            self.error = error
        }
    }
}

extension MailService {
    /// The service's name, as its own brand writes it.
    var displayName: String {
        switch self {
        case .gmail: "Gmail"
        case .icloud: "iCloud"
        }
    }

    /// What the chooser shows beside the name.
    var symbol: String {
        switch self {
        case .gmail: "envelope.fill"
        case .icloud: "icloud.fill"
        }
    }
}
