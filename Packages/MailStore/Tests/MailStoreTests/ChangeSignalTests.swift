import Foundation
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
}
