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
    /// What the server supports, `nil` until it has said.
    private(set) var capabilities: Set<String>?
    /// Extensions `enable(_:)` turned on, such as QRESYNC.
    private(set) var enabled: Set<String> = []
    private let transport: any IMAPTransport
    private var framer = IMAPFramer()
    private var nextTag = 1
    private var queue = SerialQueue()

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

    /// Asks for the server's capabilities, for a server that didn't list them in its greeting or login reply.
    func refreshCapabilities() async throws {
        try await exclusively { connection in
            let reply = try await connection.run(.capability)
            for values in reply.data where values.first?.atom?.uppercased() == "CAPABILITY" {
                connection.capabilities = Set(values.dropFirst().compactMap { $0.atom?.uppercased() })
            }
        }
    }

    /// Turns on `capability` for the rest of the session (RFC 5161).
    func enable(_ capability: String) async throws {
        try await exclusively { connection in
            try connection.requireAuthenticated()
            let reply = try await connection.run(.enable(capability))
            for values in reply.data where values.first?.atom?.uppercased() == "ENABLED" {
                connection.enabled.formUnion(values.dropFirst().compactMap { $0.atom?.uppercased() })
            }
        }
    }

    /// A mailbox's counters, without selecting it.
    func status(of mailbox: String) async throws -> IMAPFolderStatus {
        try await exclusively { connection in
            try connection.requireAuthenticated()
            let reply = try await connection.run(.status(mailbox))
            guard let status = reply.data.lazy.compactMap(IMAPFolderStatus.init(statusResponse:)).first else {
                throw IMAPError.invalid(reply.completion)
            }
            return status
        }
    }

    /// The UIDs of the selected mailbox's messages that match `search`, ascending.
    func searchUIDs(_ search: IMAPSearch) async throws -> [UInt32] {
        try await exclusively { connection in
            try connection.requireSelected()
            let found = try await connection.run(.uidSearch(search)).data.flatMap { values -> [UInt32] in
                guard values.first?.atom?.uppercased() == "SEARCH" else { return [] }
                return values.dropFirst().compactMap(\.number)
            }
            // `n:*` always matches the last message, even when its UID is below n (RFC 3501 §6.4.8).
            return found.filter { search.uids?.contains($0) ?? true }.sorted()
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

    /// These messages of the selected mailbox, whole. Messages that are gone are left out.
    func messages(_ uids: [UInt32]) async throws -> [IMAPMessageContent] {
        guard !uids.isEmpty else { return [] }
        return try await exclusively { connection in
            try connection.requireSelected()
            let reply = try await connection.run(.uidFetch(uids: uids, items: IMAPCommand.messageItems))
            return reply.data.compactMap { IMAPFetch(response: $0).flatMap(IMAPMessageContent.init(fetch:)) }
        }
    }

    /// What changed in the selected mailbox after `modSeq`: the UIDs whose flags changed, and when QRESYNC is
    /// enabled, the UIDs expunged. Without QRESYNC, `expunged` is `nil`: the server can't say.
    func changes(sinceModSeq modSeq: UInt64) async throws -> (flagged: [UInt32], expunged: [UInt32]?) {
        try await exclusively { connection in
            try connection.requireSelected()
            let vanished = connection.enabled.contains("QRESYNC")
            let reply = try await connection.run(.uidFetchChanged(sinceModSeq: modSeq, vanished: vanished))
            let flagged = reply.data.compactMap { IMAPFetch(response: $0)?.items["UID"]?.number }
            guard vanished else { return (flagged, nil) }
            let expunged = reply.data.flatMap { values -> [UInt32] in
                guard values.first?.atom?.uppercased() == "VANISHED", let set = values.last?.atom else { return [] }
                return IMAPCommand.uids(inSequenceSet: set)
            }
            return (flagged, expunged)
        }
    }

    /// Adds `flags` to these messages of the selected mailbox, or removes them.
    func store(_ flags: Set<String>, add: Bool, on uids: [UInt32]) async throws {
        guard !uids.isEmpty, !flags.isEmpty else { return }
        try await exclusively { connection in
            try connection.requireSelected()
            _ = try await connection.run(.uidStore(uids: uids, flags: flags, add: add))
        }
    }

    /// Copies these messages of the selected mailbox to `mailbox`, or moves them there. Returns each message's UID
    /// in `mailbox`, by its UID here, as the server's COPYUID names them (RFC 4315); `nil` when it doesn't say.
    func transfer(_ uids: [UInt32], to mailbox: String, move: Bool) async throws -> IMAPCopy? {
        guard !uids.isEmpty else { return nil }
        return try await exclusively { connection in
            try connection.requireSelected()
            let command =
                move ? IMAPCommand.uidMove(uids: uids, mailbox: mailbox) : .uidCopy(uids: uids, mailbox: mailbox)
            let reply = try await connection.run(command)
            return (reply.statuses + [reply.completion]).lazy.compactMap(IMAPCopy.init(status:)).first
        }
    }

    /// Removes these messages of the selected mailbox for good.
    func expunge(_ uids: [UInt32]) async throws {
        guard !uids.isEmpty else { return }
        try await exclusively { connection in
            try connection.requireSelected()
            _ = try await connection.run(.uidStore(uids: uids, flags: [#"\Deleted"#], add: true))
            _ = try await connection.run(.uidExpunge(uids: uids))
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
        try await queue.run { try await operation(self) }.value
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
