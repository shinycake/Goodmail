import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
struct MailboxesTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal)

    private func thread(labels: Set<String>) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t"), subject: "", snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: .now, isUnread: true, messageCount: 1,
            labelIDs: labels)
    }

    @Test func theListShowsStandardMailboxesThenLabelsWithUnreadCounts() async {
        let receipts = Mailbox(labelID: "Label_1", accountID: account.id)
        let directory = MailboxDirectory(
            labels: [MailboxDirectory.Label(mailbox: receipts, name: "Receipts", color: "#16a765")],
            unreadCounts: [.inbox: 4, .spam: 9, .allMail: 30, receipts: 2])
        var routes: [Route] = []
        let viewModel = MailboxesViewModel(
            accounts: [account],
            directory: {
                AsyncThrowingStream {
                    $0.yield(directory)
                    $0.finish()
                }
            },
            navigate: { routes.append($0) })
        await viewModel.observe()

        #expect(
            viewModel.standardItems.map(\.title) == ["Inbox", "Starred", "Sent", "Drafts", "All Mail", "Spam", "Trash"])
        #expect(viewModel.standardItems.first?.unreadCount == 4)
        #expect(viewModel.standardItems.first { $0.mailbox == .spam }?.unreadCount == 0, "Spam's unread isn't waiting")
        #expect(viewModel.standardItems.first { $0.mailbox == .allMail }?.unreadCount == 0, "it repeats the rest")
        #expect(viewModel.labelItems.map(\.title) == ["Receipts"])
        #expect(viewModel.labelItems.first?.unreadCount == 2)

        viewModel.open(receipts)
        viewModel.compose()
        #expect(routes.first == .mailbox(receipts))
        if case .compose(let draft) = routes.last { #expect(draft.accountID == account.id) } else { Issue.record() }
    }

    @Test func aLabelsTitleIsItsName() {
        let label = Mailbox(labelID: "Label_7", accountID: account.id)
        let named = [MailboxDirectory.Label(mailbox: label, name: "Travel", color: nil)]
        #expect(label.title(labels: named) == "Travel")
        #expect(label.title(labels: []) == "Label_7", "the ID until the labels load")
        #expect(Mailbox.trash.title(labels: []) == "Trash")
    }

    @Test func swipingTakesTheThreadOutOfWhereItIs() {
        #expect(MailboxViewModel.trailingActions(for: thread(labels: ["INBOX"])) == [.archive, .trash])
        #expect(MailboxViewModel.trailingActions(for: thread(labels: ["Label_1"])) == [.trash])
        #expect(MailboxViewModel.trailingActions(for: thread(labels: ["SPAM"])) == [.moveToInbox, .trash])
        #expect(MailboxViewModel.trailingActions(for: thread(labels: ["TRASH", "STARRED"])) == [.untrash])
    }

    @Test func aShortListFetchesOlderMailWithoutAScroll() async {
        var loads = 0
        let viewModel = MailboxViewModel(
            mailbox: .trash,
            accounts: [account],
            threads: {
                AsyncThrowingStream {
                    $0.yield([])
                    $0.finish()
                }
            },
            refresh: {},
            loadOlder: {
                loads += 1
                return false
            })
        await viewModel.observe()
        for _ in 0..<20 where loads == 0 { await Task.yield() }
        #expect(loads == 1, "Trash starts empty, so it fetches a page")
        #expect(viewModel.title == "Trash")
    }
}
