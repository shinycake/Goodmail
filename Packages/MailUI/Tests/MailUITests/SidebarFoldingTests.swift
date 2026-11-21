import Foundation
import MailCore
import Testing

@testable import MailUI

/// Folding the sidebar's sections: which stay folded on this device, and the unread count a folded header shows.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SidebarFoldingTests {
    private let defaults = UserDefaults(suiteName: "SidebarFoldingTests-\(UUID().uuidString)")!
    private let home = Account(id: AccountID(rawValue: "h"), email: "home@example.com", color: .teal, service: .gmail)
    private let work = Account(id: AccountID(rawValue: "w"), email: "work@example.com", color: .orange, service: .gmail)

    @Test func everySectionStartsUnfolded() {
        let folded = FoldedSections(defaults: defaults)
        #expect(!folded.isFolded(.labels))
        #expect(!folded.isFolded(.account(home)))
    }

    @Test func aFoldedSectionStaysFoldedForTheNextLaunch() {
        FoldedSections(defaults: defaults).set(.account(work), folded: true)
        let later = FoldedSections(defaults: defaults)
        #expect(later.isFolded(.account(work)))
        #expect(!later.isFolded(.account(home)), "each section folds on its own")
        later.set(.account(work), folded: false)
        #expect(!FoldedSections(defaults: defaults).isFolded(.account(work)))
    }

    @Test func anAccountsSectionIsKnownByTheAccountNotItsAddress() {
        FoldedSections(defaults: defaults).set(.account(work), folded: true)
        let renamed = Account(id: work.id, email: "new@example.com", color: .pink, service: .gmail)
        #expect(FoldedSections(defaults: defaults).isFolded(.account(renamed)))
    }

    @Test func foldingStaysOnThisDevice() throws {
        // The lists sync their own items, whatever their key; the defaults that sync are the values named here.
        let values = Preferences.syncedSettings.compactMap { $0 as? DefaultsValues }
        #expect(try values.allSatisfy { try !$0.local().scope.covers(FoldedSections.key) })
    }

    @Test func aFoldedHeaderCountsTheUnreadOfEveryRowInIt() async {
        let clients = Mailbox(labelID: "Label_9", accountID: work.id)
        let big = Mailbox(labelID: "Label_10", accountID: work.id)
        let workInbox = Mailbox(labelID: SystemLabel.inbox, accountID: work.id)
        let directory = MailboxDirectory(
            labels: [
                MailboxDirectory.Label(mailbox: clients, name: "Clients", color: nil),
                MailboxDirectory.Label(mailbox: big, name: "Clients/Big", color: nil),
            ],
            unreadCounts: [.inbox: 9, workInbox: 3, clients: 1, big: 2],
            snoozedCount: 4)
        let viewModel = MailboxesViewModel(
            accounts: [home, work],
            directory: {
                AsyncThrowingStream {
                    $0.yield(directory)
                    $0.finish()
                }
            })
        await viewModel.observe()

        let groups = viewModel.groups
        #expect(groups.first { $0.section == .account(work) }?.unread == 6, "the Inbox, a label and the one in it")
        #expect(groups.first { $0.section == .account(home) }?.unread == 0)
        #expect(groups.first { $0.section == .mailboxes }?.unread == 9, "snoozed threads aren't unread")
    }
}
