import Foundation
import MailCore

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
    private let transport: any MailTransport
    private var framer = IMAPFramer()
    private var nextTag = 1
    private var queue = SerialQueue()

    /// Reads the server's greeting, then with `.startTLS` turns on TLS before anything else is said (RFC 2595
    /// §3.1). Throws `IMAPError.insecure` when the server won't, or has already logged the connection in while
    /// it was plain. A connection that fails to open is closed.
    init(transport: any MailTransport, security: MailServer.Security) async throws {
        self.transport = transport
        state = .closed
        do {
            guard case .status(let greeting) = try await nextResponse() else { throw IMAPError.closed }
            switch greeting.condition {
            case .ok: state = .notAuthenticated
            case .preauth: state = .authenticated
            case .bye, .no, .bad: throw IMAPError.closed
            }
            remember(capabilitiesIn: greeting)
            if security == .startTLS { try await startTLS() }
        } catch {
            await close()
            throw error
        }
    }

    /// Closes the connection without logging out, as when it's being replaced or its socket failed. Commands then
    /// throw `IMAPError.closed`.
    func close() async {
        state = .closed
        await transport.close()
    }

    private func startTLS() async throws {
        guard state == .notAuthenticated else { throw IMAPError.insecure }
        if capabilities == nil { try await refreshedCapabilities() }
        guard capabilities?.contains("STARTTLS") == true else { throw IMAPError.insecure }
        _ = try await run(.startTLS)
        try await transport.startTLS()
        // Nothing the server said before TLS can be trusted (RFC 2595 §3.1): bytes that came after its OK are
        // dropped, and the session asks for the capabilities again.
        framer = IMAPFramer()
        capabilities = nil
    }

    func login(user: String, password: String) async throws {
        try await exclusively { connection in
            guard connection.state == .notAuthenticated else { throw IMAPError.wrongState }
            do {
                _ = try await connection.run(.login(user: user, password: password))
                // Capabilities change at login (RFC 3501 §6.2.3), and iCloud's login reply lists only the
                // AUTH= ones, so the session asks again.
                connection.capabilities = nil
            } catch IMAPError.refused(let status) where status.code("UNAVAILABLE") == nil {
                // A NO to LOGIN is a refused user name or password (RFC 3501 §6.2.3), with or without iCloud's
                // AUTHENTICATIONFAILED code; only UNAVAILABLE says the server can't check them now (RFC 5530).
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

    /// Makes a mailbox, by its name on the wire.
    func create(_ mailbox: String) async throws {
        try await exclusively { connection in
            try connection.requireAuthenticated()
            _ = try await connection.run(.create(mailbox))
        }
    }

    func rename(_ mailbox: String, to name: String) async throws {
        try await exclusively { connection in
            try connection.requireAuthenticated()
            _ = try await connection.run(.rename(mailbox, to: name))
        }
    }

    /// Deletes a mailbox. Deleting the selected one leaves none selected.
    func delete(_ mailbox: String) async throws {
        try await exclusively { connection in
            try connection.requireAuthenticated()
            if case .selected(let selection) = connection.state, selection.mailbox == mailbox {
                connection.state = .authenticated
            }
            _ = try await connection.run(.delete(mailbox))
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

    /// Asks for the server's capabilities, which the session does after login.
    func refreshCapabilities() async throws {
        try await exclusively { connection in try await connection.refreshedCapabilities() }
    }

    private func refreshedCapabilities() async throws {
        let reply = try await run(.capability)
        for values in reply.data where values.first?.atom?.uppercased() == "CAPABILITY" {
            capabilities = Set(values.dropFirst().compactMap { $0.atom?.uppercased() })
        }
    }

    /// Turns on `capability` for the rest of the session (RFC 5161).
    func enable(_ capability: String) async throws {
        try await exclusively { connection in
            try connection.requireAuthenticated()
            _ = try await connection.run(.enable(capability))
            // A server ignores what it doesn't support and still says OK (RFC 5161 §3.1). iCloud also leaves out
            // the `* ENABLED` line, so an advertised capability counts as on once ENABLE succeeds.
            let name = capability.uppercased()
            if connection.capabilities?.contains(name) == true { connection.enabled.insert(name) }
        }
    }

    /// A mailbox's counters, without selecting it.
    func status(of mailbox: String) async throws -> IMAPFolderStatus {
        try await exclusively { connection in
            try connection.requireAuthenticated()
            let modSeq = connection.capabilities?.contains("CONDSTORE") == true
            let reply = try await connection.run(.status(mailbox, modSeq: modSeq))
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
    ///
    /// A move is a MOVE (RFC 6851), tried even when the server doesn't advertise it, as iCloud doesn't. A server
    /// that doesn't know the command answers BAD and has done nothing, so the messages are copied, then expunged.
    func transfer(_ uids: [UInt32], to mailbox: String, move: Bool) async throws -> IMAPCopy? {
        guard !uids.isEmpty else { return nil }
        return try await exclusively { connection in
            try connection.requireSelected()
            guard move else { return try await connection.copy(uids, to: mailbox) }
            do {
                let reply = try await connection.run(.uidMove(uids: uids, mailbox: mailbox))
                return (reply.statuses + [reply.completion]).lazy.compactMap(IMAPCopy.init(status:)).first
            } catch IMAPError.invalid where connection.capabilities?.contains("MOVE") != true {
                let copy = try await connection.copy(uids, to: mailbox)
                try await connection.markDeletedAndExpunge(uids)
                return copy
            }
        }
    }

    /// Removes these messages of the selected mailbox for good.
    func expunge(_ uids: [UInt32]) async throws {
        guard !uids.isEmpty else { return }
        try await exclusively { connection in
            try connection.requireSelected()
            try await connection.markDeletedAndExpunge(uids)
        }
    }

    private func copy(_ uids: [UInt32], to mailbox: String) async throws -> IMAPCopy? {
        let reply = try await run(.uidCopy(uids: uids, mailbox: mailbox))
        return (reply.statuses + [reply.completion]).lazy.compactMap(IMAPCopy.init(status:)).first
    }

    /// Flags these messages `\Deleted` and expunges them. Without UIDPLUS (RFC 4315) EXPUNGE can't name them, so it
    /// also removes whatever else in the mailbox was flagged `\Deleted`, as every IMAP client's EXPUNGE does.
    private func markDeletedAndExpunge(_ uids: [UInt32]) async throws {
        _ = try await run(.uidStore(uids: uids, flags: [#"\Deleted"#], add: true))
        _ = try await run(capabilities?.contains("UIDPLUS") == true ? .uidExpunge(uids: uids) : .expunge)
    }

    /// Adds `message` to `mailbox` with `flags`. Returns its UID there when the server says (APPENDUID, RFC 4315).
    func append(_ message: Data, to mailbox: String, flags: Set<String>) async throws -> MessageUID? {
        try await exclusively { connection in
            try connection.requireAuthenticated()
            let reply = try await connection.run(.append(mailbox: mailbox, flags: flags, message: message))
            guard let code = reply.completion.code("APPENDUID"), code.count == 2, let uidValidity = code[0].number,
                let uid = code[1].number
            else { return nil }
            return MessageUID(uidValidity: uidValidity, uid: uid)
        }
    }

    /// Logs out and closes the connection, also when the server doesn't answer.
    func logout() async throws {
        try await exclusively { connection in
            guard connection.state != .closed else { return }
            do {
                _ = try await connection.run(.logout)
            } catch {
                await connection.close()
                throw error
            }
            await connection.close()
        }
    }

    // MARK: - Running commands

    /// Runs `operation` after every command called before it has finished.
    private func exclusively<T: Sendable>(
        _ operation: @escaping @Sendable (isolated IMAPConnection) async throws -> T
    ) async throws -> T {
        try await queue.run { try await operation(self) }.value
    }

    /// Sends `command` and reads up to its completion. Returns the untagged data that came with it. A command with
    /// literals sends each one when the server asks for it.
    private func run(_ command: IMAPCommand) async throws -> IMAPReply {
        guard state != .closed else { throw IMAPError.closed }
        let tag = "A\(nextTag)"
        nextTag += 1
        var parts = try command.parts(tag: tag)[...]
        try await send(parts.removeFirst())
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
            case .continuation:
                guard let next = parts.popFirst() else {
                    throw IMAPError.invalid(IMAPStatus(condition: .bad, text: "Unexpected +"))
                }
                try await send(next)
            case .completion:
                // No other command is in flight.
                continue
            }
        }
    }

    private func nextResponse() async throws -> IMAPResponse {
        while true {
            if let response = framer.next() { return try IMAPParser.response(from: response) }
            let bytes = try await receive()
            guard !bytes.isEmpty else {
                await close()
                throw IMAPError.closed
            }
            framer.append(bytes)
        }
    }

    /// Writes to the socket. A socket that fails has lost the connection, as one the server dropped while it was idle
    /// does, so the connection closes and its owner opens a new one. The socket's error, such as `Network.NWError`
    /// 57, goes on up to say why.
    private func send(_ data: Data) async throws {
        do {
            try await transport.send(data)
        } catch {
            await close()
            throw error
        }
    }

    /// Reads from the socket, closing the connection when the socket fails, as `send(_:)` does.
    private func receive() async throws -> Data {
        do {
            return try await transport.receive()
        } catch {
            await close()
            throw error
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
