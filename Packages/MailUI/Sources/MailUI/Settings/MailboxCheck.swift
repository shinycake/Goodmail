public import Observation

/// Whether Goodmail's push server may look at a Gmail account's history, so it alerts only when new mail reaches the
/// Inbox instead of for every read, archive or delete. Every state change happens in `load()` or `set(_:)`.
@Observable
public final class MailboxCheck {
    public enum State: Equatable {
        case loading
        /// The server couldn't say, so there is nothing to switch.
        case unknown
        case off
        case on
        /// Google's consent page or the server is answering a switch to `on`.
        case changing(to: Bool)
    }

    /// How to reach the server and Google for one account.
    public struct Service {
        /// Whether the server holds the account's grant; `nil` when it couldn't be asked.
        public let isOn: () async -> Bool?
        /// Shows Google's consent page and hands the grant to the server. `false` when the reader cancelled or it
        /// failed.
        public let turnOn: () async -> Bool
        /// Has the server drop the grant. `false` when it couldn't be reached.
        public let turnOff: () async -> Bool

        public init(
            isOn: @escaping () async -> Bool?, turnOn: @escaping () async -> Bool,
            turnOff: @escaping () async -> Bool
        ) {
            self.isOn = isOn
            self.turnOn = turnOn
            self.turnOff = turnOff
        }
    }

    public private(set) var state: State = .loading
    @ObservationIgnored private let service: Service

    public init(service: Service) {
        self.service = service
    }

    func load() async {
        guard state == .loading || state == .unknown else { return }
        state = .loading
        state = Self.state(await service.isOn())
    }

    /// Switches the check. A switch that didn't go through leaves it as it was.
    func set(_ on: Bool) async {
        guard state == .off || state == .on, (state == .on) != on else { return }
        let before = state
        state = .changing(to: on)
        let done = on ? await service.turnOn() : await service.turnOff()
        state = done ? (on ? .on : .off) : before
    }

    private static func state(_ isOn: Bool?) -> State {
        switch isOn {
        case true?: .on
        case false?: .off
        case nil: .unknown
        }
    }
}
