import Foundation

/// One IMAP session (RFC 3501 §3): log in, open a mailbox, read it. Commands run one at a time, in call order.
actor IMAPConnection {
    /// Where the session stands. Each command checks it, and only `run(_:)` changes it.
    enum State: Equatable, Sendable {
        case notAuthenticated
        case authenticated
        case selected(IMAPSelection)
        case closed
    }

    private(set) var state: State
    private(set) var capabilities: Set<String> = []
    private let transport: any IMAPTransport
    private var framer = IMAPFramer()
    private var nextTag = 1
    /// The command running now; the next one waits for it.
    private var tail: Task<Void, Never>?

    /// Connects and reads the server's greeting.
    init(transport: any IMAPTransport) async throws {
        self.transport = transport
        state = .closed
        guard case .status(let greeting) = try await nextResponse() else { throw IMAPError.closed }
        switch greeting.condition {
        case .ok: state = .notAuthenticated
        case .preauth: state = .authenticated
        case .bye, .no, .bad: throw IMAPError.closed
        }
        remember(capabilitiesIn: greeting)
    }

    func login(user: String, password: String) async throws {
        try await exclusively { connection in
            guard connection.state == .notAuthenticated else { throw IMAPError.wrongState }
            do {
                let reply = try await connection.run(.login(user: user, password: password))
                connection.remember(capabilitiesIn: reply.completion)
            } catch IMAPError.refused(let status) where status.code("AUTHENTICATIONFAILED") != nil {
                throw IMAPError.authenticationFailed
            }
            connection.state = .authenticated
        }
    }

    func mailboxes() async throws -> [IMAPMailbox] {
        try await exclusively { connection in
            try connection.requireAuthenticated()
            return try await connection.run(.list).data.compactMap(IMAPMailbox.init(listResponse:))
        }
    }

    /// Opens `mailbox`, by its name on the wire, for searching and fetching.
    @discardableResult
    func select(_ mailbox: String) async throws -> IMAPSelection {
        try await exclusively { connection in
            try connection.requireAuthenticated()
            // A failed SELECT leaves no mailbox selected (RFC 3501 §6.3.1).
            connection.state = .authenticated
            let selection = try IMAPSelection(mailbox: mailbox, reply: try await connection.run(.select(mailbox)))
            connection.state = .selected(selection)
            return selection
        }
    }

    /// The UIDs of the selected mailbox's messages received on or after `since`'s day, ascending.
    func searchUIDs(since: Date) async throws -> [UInt32] {
        try await exclusively { connection in
            try connection.requireSelected()
            return try await connection.run(.uidSearch(since: since)).data.flatMap { values -> [UInt32] in
                guard values.first?.atom?.uppercased() == "SEARCH" else { return [] }
                return values.dropFirst().compactMap(\.number)
            }.sorted()
        }
    }

    /// The headers of these messages in the selected mailbox. Messages that are gone are left out.
    func headers(of uids: [UInt32]) async throws -> [IMAPMessageHeader] {
        guard !uids.isEmpty else { return [] }
        return try await exclusively { connection in
            try connection.requireSelected()
            let reply = try await connection.run(.uidFetch(uids: uids, items: IMAPCommand.headerItems))
            return reply.data.compactMap { IMAPFetch(response: $0).flatMap(IMAPMessageHeader.init(fetch:)) }
        }
    }

    func logout() async throws {
        try await exclusively { connection in
            guard connection.state != .closed else { return }
            _ = try await connection.run(.logout)
            connection.state = .closed
        }
    }

    // MARK: - Running commands

    /// Runs `operation` after every command called before it has finished.
    private func exclusively<T: Sendable>(
        _ operation: @escaping @Sendable (isolated IMAPConnection) async throws -> T
    ) async throws -> T {
        let previous = tail
        let task = Task {
            await previous?.value
            return try await operation(self)
        }
        tail = Task { _ = await task.result }
        return try await task.value
    }

    /// Sends `command` and reads up to its completion. Returns the untagged data that came with it.
    private func run(_ command: IMAPCommand) async throws -> IMAPReply {
        guard state != .closed else { throw IMAPError.closed }
        let tag = "A\(nextTag)"
        nextTag += 1
        try await transport.send(try command.line(tag: tag))
        var reply = IMAPReply()
        while true {
            switch try await nextResponse() {
            case .data(let values):
                reply.data.append(values)
            case .completion(tag, let status):
                switch status.condition {
                case .ok:
                    reply.completion = status
                    return reply
                case .no: throw IMAPError.refused(status)
                case .bad, .bye, .preauth: throw IMAPError.invalid(status)
                }
            case .status(let status):
                remember(capabilitiesIn: status)
                reply.statuses.append(status)
            case .completion, .continuation:
                // Nothing Goodmail sends waits for a continuation, and no other command is in flight.
                continue
            }
        }
    }

    private func nextResponse() async throws -> IMAPResponse {
        while true {
            if let response = framer.next() { return try IMAPParser.response(from: response) }
            let bytes = try await transport.receive()
            guard !bytes.isEmpty else {
                state = .closed
                throw IMAPError.closed
            }
            framer.append(bytes)
        }
    }

    private func remember(capabilitiesIn status: IMAPStatus) {
        guard let names = status.code("CAPABILITY") else { return }
        capabilities = Set(names.compactMap { $0.atom?.uppercased() })
    }

    private func requireAuthenticated() throws {
        switch state {
        case .authenticated, .selected: return
        case .notAuthenticated, .closed: throw IMAPError.wrongState
        }
    }

    private func requireSelected() throws {
        guard case .selected = state else { throw IMAPError.wrongState }
    }
}

/// What came back for one command: its untagged responses, then its completion.
struct IMAPReply: Sendable {
    var data: [[IMAPValue]] = []
    var statuses: [IMAPStatus] = []
    var completion = IMAPStatus(condition: .ok)
}
