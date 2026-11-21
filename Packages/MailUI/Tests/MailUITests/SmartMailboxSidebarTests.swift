import Foundation
import MailCore
import Testing

@testable import MailUI

/// The Smart Mailboxes section of the sidebar: after the standard mailboxes, before the accounts, with each box's
/// unread count, opening its list.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SmartMailboxSidebarTests {
    private let one = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal, service: .gmail)
    private let two = Account(id: AccountID(rawValue: "w"), email: "w@example.com", color: .orange, service: .gmail)

    private func viewModel(accounts: [Account], navigate: @escaping (Route) -> Void = { _ in }) -> MailboxesViewModel {
        let smart = SmartMailboxDirectory(
            mailboxes: SmartMailbox.startingSet, unreadCounts: [SmartMailbox.startingSet[0].id: 5])
        return MailboxesViewModel(
            accounts: accounts,
            directory: { AsyncThrowingStream { $0.finish() } },
            smartMailboxes: {
                AsyncThrowingStream {
                    $0.yield(smart)
                    $0.finish()
                }
            },
            navigate: navigate)
    }

    @Test func theSectionFollowsTheStandardMailboxesAndPrecedesTheAccounts() async {
        let several = viewModel(accounts: [one, two])
        await several.observe()
        #expect(several.groups.map(\.section) == [.mailboxes, .smartMailboxes, .account(one), .account(two)])
        let single = viewModel(accounts: [one])
        await single.observe()
        #expect(single.groups.map(\.section) == [.mailboxes, .smartMailboxes], "no labels yet")
        let rows = several.groups[1].items
        #expect(rows.map(\.symbol) == ["envelope.badge", "crown", "paperclip"])
        #expect(rows.map(\.count) == [5, 0, 0])
    }

    @Test func aBoxOpensItsList() async {
        var routes: [Route] = []
        let sidebar = viewModel(accounts: [one], navigate: { routes.append($0) })
        await sidebar.observe()
        let vips = SmartMailbox.startingSet[1].id
        sidebar.open(.smart(vips))
        #expect(routes == [.smartMailbox(vips)])
    }
}
