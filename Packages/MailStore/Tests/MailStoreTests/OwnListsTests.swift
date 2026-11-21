import Foundation
import MailCore
import Testing

@testable import MailStore

/// The labels and smart mailboxes a window's list is checked against, as they change.
struct OwnListsTests {
    private let database: MailDatabase
    private let account = Account(id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)

    init() throws {
        database = try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "OwnListsTests-\(UUID().uuidString)")
                .appending(path: "mail.sqlite"))
        try database.save(account)
    }

    private func label(_ id: String) -> Mailbox {
        Mailbox(labelID: id, accountID: account.id)
    }

    @Test func theListsFollowLabelsAndSmartMailboxesAsTheyChange() async throws {
        let starting = Set(SmartMailbox.startingSet.map(\.id))
        var lists = database.ownLists().makeAsyncIterator()
        #expect(try await lists.next() == WindowState.OwnLists(labels: [], smartMailboxes: starting))

        let labels = [
            MailLabel(id: SystemLabel.inbox, name: "INBOX", kind: .system),
            MailLabel(id: "Label_7", name: "Receipts", kind: .user, isHidden: true),
        ]
        try database.apply(StoreChanges(accountID: account.id, labels: labels))
        #expect(
            try await lists.next()
                == WindowState.OwnLists(labels: [label(SystemLabel.inbox), label("Label_7")], smartMailboxes: starting),
            "hidden labels too, since a window can still show one")

        let removed = try #require(SmartMailbox.startingSet.first?.id)
        try database.deleteSmartMailbox(removed)
        #expect(try await lists.next()?.smartMailboxes == starting.subtracting([removed]))
    }
}
