import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One attempt at uploading a message. A new attempt gets a new ID, so a late outcome of an old one is ignored.
public struct UploadID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

/// What the transport labels an upload with, and hands back with its outcome: whose it is, and which attempt.
public struct UploadTicket: Hashable, Sendable, LosslessStringConvertible {
    public let accountID: AccountID
    public let id: UploadID

    public init(accountID: AccountID, id: UploadID) {
        self.accountID = accountID
        self.id = id
    }

    public var description: String { "\(id.rawValue.uuidString) \(accountID.rawValue)" }

    public init?(_ description: String) {
        let parts = description.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, let id = UUID(uuidString: String(parts[0])) else { return nil }
        self.init(accountID: AccountID(rawValue: String(parts[1])), id: UploadID(rawValue: id))
    }
}

/// A send made ready for an upload that outlives the app: the request, with fresh credentials, and its body.
public struct PreparedSend: Sendable {
    public var request: URLRequest
    public var body: Data

    public init(request: URLRequest, body: Data) {
        self.request = request
        self.body = body
    }
}

/// How a provider sends a message.
public enum Sending: Sendable {
    /// Over the provider's own connection, while the app runs, as SMTP does: sends an RFC 5322 message, in the
    /// thread it answers when there is one. Throws `ProviderError.rejected` for a message the service won't send.
    case direct(@Sendable (_ raw: Data, _ threadID: String?) async throws -> Void)
    /// As a single upload that a transfer outliving the app carries, as Gmail's API allows.
    case upload(any UploadSending)
}

/// A provider whose sends are uploads (`Sending.upload`): it prepares each one, reads the answer, and says
/// whether a message whose answer never came went anyway.
public protocol UploadSending: Sendable {
    /// Prepares an RFC 5322 message for sending, in `threadID` when it answers one, as a single upload whose
    /// request carries fresh credentials. The upload itself runs outside the provider.
    func prepareSend(_ raw: Data, inThread threadID: String?) async throws -> PreparedSend

    /// What the service's answer to a prepared send says happened.
    func answer(status: Int, body: Data) -> SendAnswer

    /// Whether the account's sent mail holds a message with this `Message-ID` header (without the angle brackets).
    func hasSent(messageID: String) async throws -> Bool
}

/// What a service's answer to a send upload says happened, and so what the send queue does next.
public enum SendAnswer: Equatable, Sendable {
    /// The message went.
    case sent
    /// The service won't send it as it is; sending it again won't help.
    case rejected
    /// The thread it answers is gone; it can go on its own.
    case threadGone
    /// Turned away unread, as for a rate limit or an expired token, so it can safely be sent again.
    case turnedAway
    /// The service failed partway and may have sent it already, so whether it went is asked before anything else.
    case unknown
}

/// How an upload ended.
public enum UploadOutcome: Equatable, Sendable {
    /// The provider answered.
    case response(status: Int, body: Data)
    /// The transfer ended without an answer, cancelled or cut off. The message may or may not have gone.
    case noResponse
}

/// Uploads that carry on while the app is suspended or gone: a background `URLSession` in the app. Each outcome
/// comes back to the account's `Sender.complete`, on this launch or a later one.
public protocol UploadTransport: Sendable {
    /// Starts uploading `file` with `request`, labelled `ticket`.
    func upload(_ request: URLRequest, from file: URL, ticket: UploadTicket) async throws
    /// The uploads still under way, whatever launch started them.
    func activeUploads() async -> Set<UploadID>
}

/// The bodies handed to the transport, one file per upload, kept until its outcome is in. Background uploads must
/// come from a file.
struct UploadFiles {
    let directory: URL

    func write(_ body: Data, for id: UploadID) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = url(for: id)
        try body.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return file
    }

    func remove(_ id: UploadID) {
        try? FileManager.default.removeItem(at: url(for: id))
    }

    /// Removes the files of every upload but `kept`, such as one written just before the app was killed.
    func removeAll(except kept: Set<UploadID>) {
        let names = Set(kept.map { url(for: $0).lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !names.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func url(for id: UploadID) -> URL {
        directory.appending(path: "\(id.rawValue.uuidString).upload")
    }
}
