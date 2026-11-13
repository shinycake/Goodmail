import Foundation
import MailCore

@testable import MailStore

/// A send queue on a real database, against a fake server and a fake background session.
struct SendBench {
    let database: MailDatabase
    let server: FakeMailServer
    let uploads: FakeUploads
    let account = AccountID(rawValue: "a1")
    let clock = TickingClock(start: Date(timeIntervalSince1970: 1_800_000_000))
    let uploadsDirectory: URL

    init(sendPath: FakeMailServer.SendPath = .upload) throws {
        server = FakeMailServer(sendPath: sendPath)
        let folder = FileManager.default.temporaryDirectory.appending(path: "SendBench-\(UUID().uuidString)")
        database = try MailDatabase(url: folder.appending(path: "mail.sqlite"))
        try database.save(Account(id: account, email: "me@example.com", color: .teal, service: .gmail))
        uploads = FakeUploads(server: server)
        uploadsDirectory = folder.appending(path: "Uploads")
    }

    func commands() -> MailCommands {
        MailCommands(store: database, replay: { _ in }, now: clock.next)
    }

    /// A new sender each time is a new launch: it knows only what the database and the session kept. It reads the
    /// ticking clock, or `date` when one is given.
    func sender(at date: Date? = nil) -> Sender {
        let now: @Sendable () -> Date = if let date { { date } } else { clock.next }
        return Sender(
            accountID: account, provider: server, store: database, transport: uploads, uploads: uploadsDirectory,
            now: now)
    }

    func draft(_ subject: String = "Hello") -> Draft {
        Draft(
            accountID: account, to: [Contact(name: nil, address: "dana@example.com")], subject: subject,
            body: MessageBody(html: "<div>Hi</div>", plain: "Hi"), threadID: "t1")
    }

    /// What one launch with a connection does: flushes, lets every upload finish, and takes in the outcomes.
    /// Returns the drafts that went.
    @discardableResult
    func deliver(with sender: Sender? = nil) async throws -> [Draft] {
        let sender = sender ?? self.sender()
        var went = await sender.flush()
        for (id, outcome) in try uploads.finishAll() {
            if let draft = await sender.complete(id, with: outcome) { went.append(draft) }
        }
        return went
    }

    /// The upload files left on disk for the account.
    func uploadFiles() -> [URL] {
        let folder = uploadsDirectory.appending(path: account.rawValue)
        return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
    }

    func failures() async throws -> [SendFailure?] {
        var failed = database.failedMessages().makeAsyncIterator()
        return try await failed.next()?.map(\.failure) ?? []
    }
}
