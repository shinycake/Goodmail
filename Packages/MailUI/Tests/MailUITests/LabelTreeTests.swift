import MailCore
import Testing

@testable import MailUI

// They follow the store's streams, so one that never finishes fails the test instead of hanging the run.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LabelTreeTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal, service: .gmail)

    private func label(_ id: String, _ name: String) -> MailboxDirectory.Label {
        MailboxDirectory.Label(mailbox: Mailbox(labelID: id, accountID: account.id), name: name, color: nil)
    }

    @Test func labelsNestByTheirPathsAndAStepThatIsNoLabelIsAFolder() {
        let tree = LabelTree([
            label("1", "Projects"), label("2", "Projects/Goodmail"), label("3", "Receipts/2026"),
            label("4", "Projects/Goodmail/Design"), label("5", "קבלות"),
        ])

        #expect(tree.roots.map(\.name) == ["Projects", "Receipts", "קבלות"], "a parent keeps its first label's place")
        #expect(tree.roots[0].label?.name == "Projects")
        #expect(tree.roots[0].children.map(\.name) == ["Goodmail"])
        #expect(tree.roots[0].children[0].children.map(\.path) == ["Projects/Goodmail/Design"])
        #expect(tree.roots[1].label == nil, "Receipts is no label, only a folder for 2026")
        #expect(tree.roots[1].children.map(\.label?.name) == ["Receipts/2026"])
    }

    @Test func aFoldedParentCountsItsNestedLabelsUnreadThreads() async {
        let projects = label("1", "Projects")
        let goodmail = label("2", "Projects/Goodmail")
        let design = label("3", "Projects/Goodmail/Design")
        let year = label("4", "Receipts/2026")
        let directory = MailboxDirectory(
            labels: [projects, goodmail, design, year],
            unreadCounts: [projects.mailbox: 1, goodmail.mailbox: 2, design.mailbox: 4, year.mailbox: 8])
        let viewModel = MailboxesViewModel(
            accounts: [account],
            directory: {
                AsyncThrowingStream {
                    $0.yield(directory)
                    $0.finish()
                }
            })
        await viewModel.observe()

        let labels = viewModel.groups[1]
        #expect(labels.items.map(\.title) == ["Projects", "Receipts"])
        #expect(labels.items.map(\.count) == [1, 0])
        #expect(labels.items.map(\.nestedCount) == [7, 8])
        #expect(labels.items.map(\.isParent) == [true, true])
        #expect(labels.children[.mailbox(goodmail.mailbox)]?.map(\.isParent) == [false])
        let folder = MailboxesViewModel.Destination.folder(path: "Receipts", accountID: account.id)
        #expect(labels.items[1].destination == folder)
        #expect(labels.children[folder]?.map(\.title) == ["2026"])
        #expect(labels.children[.mailbox(projects.mailbox)]?.map(\.title) == ["Goodmail"])
        #expect(labels.children[.mailbox(goodmail.mailbox)]?.map(\.nestedCount) == [4])
        #expect(viewModel.label(at: folder) == nil, "a folder that is no label can't be renamed or deleted")
    }
}
