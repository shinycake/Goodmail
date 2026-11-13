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

        let groups = viewModel.groups
        #expect(groups.map(\.section) == [.mailboxes, .labels])
        let standard = groups[0].items
        #expect(standard.map(\.title) == ["Inbox", "Starred", "Sent", "Drafts", "All Mail", "Spam", "Trash"])
        #expect(standard.first?.unreadCount == 4)
        #expect(standard.first { $0.mailbox == .spam }?.unreadCount == 0, "Spam's unread isn't waiting")
        #expect(standard.first { $0.mailbox == .allMail }?.unreadCount == 0, "it repeats the rest")
        #expect(groups[1].items.map(\.title) == ["Receipts"])
        #expect(groups[1].items.first?.unreadCount == 2)
        #expect(viewModel.theme == .account(.teal), "one account's list wears its color")

        viewModel.open(receipts)
        viewModel.compose()
        #expect(routes.first == .mailbox(receipts))
        if case .compose(let draft) = routes.last { #expect(draft.accountID == account.id) } else { Issue.record() }
    }

    @Test func severalAccountsListTheBlendedMailboxesThenEachAccountsInboxAndLabels() async {
        let work = Account(id: AccountID(rawValue: "w"), email: "work@example.com", color: .orange)
        let receipts = Mailbox(labelID: "Label_1", accountID: account.id)
        let clients = Mailbox(labelID: "Label_9", accountID: work.id)
        let ownInbox = Mailbox(labelID: SystemLabel.inbox, accountID: account.id)
        let workInbox = Mailbox(labelID: SystemLabel.inbox, accountID: work.id)
        let directory = MailboxDirectory(
            labels: [
                MailboxDirectory.Label(mailbox: clients, name: "Clients", color: nil),
                MailboxDirectory.Label(mailbox: receipts, name: "Receipts", color: nil),
            ],
            unreadCounts: [.inbox: 5, ownInbox: 2, workInbox: 3, clients: 1])
        let viewModel = MailboxesViewModel(
            accounts: [account, work],
            directory: {
                AsyncThrowingStream {
                    $0.yield(directory)
                    $0.finish()
                }
            })
        await viewModel.observe()

        let groups = viewModel.groups
        #expect(groups.map(\.section) == [.mailboxes, .account(account), .account(work)])
        #expect(groups[0].items.map(\.mailbox) == Mailbox.standard, "every account's, blended")
        #expect(groups[0].items.first?.unreadCount == 5)
        #expect(groups[1].items.map(\.mailbox) == [ownInbox, receipts])
        #expect(groups[1].items.map(\.unreadCount) == [2, 0])
        #expect(groups[2].items.map(\.mailbox) == [workInbox, clients])
        #expect(groups[2].items.map(\.unreadCount) == [3, 1])
        #expect(viewModel.theme == .blend(AccountBlend([.teal, .orange])))
    }

    @Test func anAccountsMailboxWearsItsColorAndComposesFromIt() {
        let work = Account(id: AccountID(rawValue: "w"), email: "work@example.com", color: .orange)
        var routes: [Route] = []
        func mailbox(_ mailbox: Mailbox) -> MailboxViewModel {
            MailboxViewModel(
                mailbox: mailbox, accounts: [account, work], source: .flat { AsyncThrowingStream { $0.finish() } },
                refresh: {}, navigate: { routes.append($0) })
        }
        let own = mailbox(Mailbox(labelID: SystemLabel.inbox, accountID: work.id))
        let blended = mailbox(.inbox)
        let workThread = ThreadSummary(
            id: ThreadSummary.ID(accountID: work.id, threadID: "t"), subject: "", snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: .now, isUnread: false, messageCount: 1,
            labelIDs: ["INBOX"])

        #expect(own.theme == .account(.orange))
        #expect(own.rowAccount(for: workThread) == .implied(.orange))
        #expect(blended.theme == .blend(AccountBlend([.teal, .orange])))
        #expect(blended.rowAccount(for: workThread) == .shown(.orange, email: "work@example.com"))

        own.compose()
        blended.compose()
        let senders = routes.compactMap { route -> AccountID? in
            guard case .compose(let draft) = route else { return nil }
            return draft.accountID
        }
        #expect(senders == [work.id, account.id], "the mailbox's own account, else the first")
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
