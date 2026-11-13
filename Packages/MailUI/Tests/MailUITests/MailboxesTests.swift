import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
struct MailboxesTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal, service: .gmail)

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
        #expect(viewModel.standardItems.first?.count == 4)
        #expect(
            viewModel.standardItems.first { $0.destination == .mailbox(.spam) }?.count == 0,
            "Spam's unread isn't waiting")
        #expect(
            viewModel.standardItems.first { $0.destination == .mailbox(.allMail) }?.count == 0, "it repeats the rest")
        #expect(viewModel.labelItems.map(\.title) == ["Receipts"])
        #expect(viewModel.labelItems.first?.count == 2)

        viewModel.open(.mailbox(receipts))
        viewModel.compose()
        #expect(routes.first == .mailbox(receipts))
        if case .compose(let draft) = routes.last { #expect(draft.accountID == account.id) } else { Issue.record() }
    }

    @Test func scheduledShowsAfterDraftsOnlyWhileAMessageWaits() async {
        func items(scheduled: Int) async -> [MailboxesViewModel.Item] {
            let viewModel = MailboxesViewModel(
                accounts: [account],
                directory: {
                    AsyncThrowingStream {
                        $0.yield(MailboxDirectory(scheduledCount: scheduled))
                        $0.finish()
                    }
                })
            await viewModel.observe()
            return viewModel.standardItems
        }
        #expect(await items(scheduled: 0).contains { $0.destination == .scheduled } == false)
        let shown = await items(scheduled: 2)
        #expect(shown.map(\.title) == ["Inbox", "Starred", "Sent", "Drafts", "Scheduled", "All Mail", "Spam", "Trash"])
        #expect(shown.first { $0.destination == .scheduled }?.count == 2)
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

    @Test func bulkActionsAreWhatEverySelectedThreadAllows() {
        var read = thread(labels: ["INBOX"])
        read.isUnread = false
        #expect(MailboxViewModel.bulkActions(for: []) == [])
        #expect(MailboxViewModel.bulkActions(for: [read]) == [.markRead(false), .archive, .trash])
        #expect(
            MailboxViewModel.bulkActions(for: [read, thread(labels: ["INBOX"])]) == [
                .markRead(true), .archive, .trash,
            ],
            "any unread one makes it Mark as Read")
        #expect(
            MailboxViewModel.bulkActions(for: [read, thread(labels: ["Label_1"])]) == [.markRead(true), .trash],
            "archived mail can't be archived again")
        #expect(MailboxViewModel.bulkActions(for: [read, thread(labels: ["TRASH"])]) == [.markRead(true)])
    }

    @Test func aShortListFetchesOlderMailWithoutAScroll() async {
        var loads = 0
        let viewModel = MailboxViewModel(
            mailbox: .trash,
            accounts: [account],
            source: .flat {
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
