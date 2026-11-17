import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// Two `MailDatabase` instances on one file stand in for the app and the Notification Service Extension.
struct ChangeSignalTests {
    @Test(.timeLimit(.minutes(1))) func aWriteInOneProcessReachesTheOthersObservation() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ChangeSignalTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        let app = try MailDatabase(url: url)
        let extensionProcess = try MailDatabase(url: url)
        let account = Account(id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
        try app.save(account)

        var inbox = app.threads(in: .inbox).makeAsyncIterator()
        #expect(try await inbox.next()?.isEmpty == true)

        try extensionProcess.upsert([
            ThreadSummary(
                id: ThreadSummary.ID(accountID: account.id, threadID: "pushed"),
                subject: "Arrived while locked",
                snippet: "",
                sender: Contact(name: nil, address: "a@example.com"),
                date: .now,
                isUnread: true,
                messageCount: 1,
                labelIDs: ["INBOX"]
            )
        ])
        #expect(try await inbox.next()?.map(\.id.threadID) == ["pushed"])
    }

    /// A suspended app can't re-check when the extension signals: the extension stored the mail it alerted for, and
    /// the inbox didn't show it, even after a refresh found nothing newer to fetch. Resuming re-checks.
    @Test(.timeLimit(.minutes(1))) func resumingShowsWhatAnotherProcessWroteMeanwhile() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "ChangeSignalTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        let app = try MailDatabase(url: url)
        let extensionProcess = try MailDatabase(url: url)
        let account = Account(id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
        try app.save(account)
        func thread(_ id: String, minutesAgo: Double) -> ThreadSummary {
            ThreadSummary(
                id: ThreadSummary.ID(accountID: account.id, threadID: id),
                subject: id,
                snippet: "",
                sender: Contact(name: nil, address: "a@example.com"),
                date: .now.addingTimeInterval(-minutesAgo * 60),
                isUnread: true,
                messageCount: 1,
                labelIDs: ["INBOX"]
            )
        }

        var inbox = app.threads(in: .inbox).makeAsyncIterator()
        #expect(try await inbox.next()?.isEmpty == true)
        // The app's own write, so the observation is past its start, which would catch the next write by itself.
        try app.upsert([thread("synced", minutesAgo: 60)])
        #expect(try await inbox.next()?.map(\.id.threadID) == ["synced"])

        // Written without the signal, as one the suspended app heard but couldn't act on.
        let pushed = thread("pushed", minutesAgo: 1)
        try await extensionProcess.pool.write { try MailDatabase.upsert(pushed, in: $0) }

        MailDatabase.resumeAll()
        #expect(try await inbox.next()?.map(\.id.threadID) == ["pushed", "synced"])
    }
}
