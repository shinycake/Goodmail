import Foundation
import MailCore
import Testing

@testable import MailUI

// They follow the store's streams, so one that never finishes fails the test instead of hanging the run.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RowShortcutAnswerTests {
    private let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal, service: .gmail)
    private let work = Account(id: AccountID(rawValue: "w"), email: "work@example.com", color: .orange, service: .gmail)

    /// The sections a sidebar folds, kept apart from the reader's own.
    private let folded = FoldedSections(
        defaults: UserDefaults(suiteName: "RowShortcutAnswerTests-\(UUID().uuidString)")!)

    private func sidebar(
        accounts: [Account]? = nil, labels: [MailboxDirectory.Label] = [], style: MailboxesViewController.Style = .list,
        routes: @escaping (Route) -> Void = { _ in }
    ) async -> MailboxesViewModel {
        let directory = MailboxDirectory(labels: labels, unreadCounts: [:])
        let viewModel = MailboxesViewModel(
            accounts: accounts ?? [account],
            directory: {
                AsyncThrowingStream {
                    $0.yield(directory)
                    $0.finish()
                }
            },
            navigate: routes, actions: MailActions(commands: MailCommands(store: NoStore(), replay: { _ in })),
            style: style, foldedSections: folded)
        await viewModel.observe()
        return viewModel
    }

    private func label(_ id: String, _ name: String) -> MailboxDirectory.Label {
        MailboxDirectory.Label(mailbox: Mailbox(labelID: id, accountID: account.id), name: name, color: nil)
    }

    private func dragged(from mailbox: Mailbox = .inbox) -> [DraggedThread] {
        [DraggedThread(id: ThreadSummary.ID(accountID: account.id, threadID: "t"), mailbox: mailbox)]
    }

    @Test func theNumbersFollowTheRowsAsTheSidebarShowsThem() async {
        let sidebar = await sidebar(labels: [
            label("L1", "Receipts"), label("L2", "Receipts/2026"), label("L3", "Work"),
        ])
        #expect(
            sidebar.numberedRows.rows.map(\.title)
                == ["Inbox", "Starred", "Sent", "Drafts", "All Mail", "Spam", "Trash", "Receipts", "2026"])
    }

    @Test func labelsFoldedAwayAndFoldersThatOpenNothingTakeNoNumber() async throws {
        // "Extra" only holds labels, so it opens nothing; folding "Receipts" takes its nested label away.
        let sidebar = await sidebar(labels: [
            label("L1", "Receipts"), label("L2", "Receipts/2026"), label("L3", "Extra/Old"),
        ])
        let before = sidebar.numberedRows.rows.map(\.title)
        #expect(before.contains("2026"))
        #expect(!before.contains("Extra"))
        let receipts = try #require(sidebar.groups.flatMap(\.items).first { $0.title == "Receipts" })
        sidebar.fold(.mailbox(receipts), folded: true)
        #expect(!sidebar.numberedRows.rows.map(\.title).contains("2026"))
    }

    @Test func rowsInAFoldedSectionTakeNoNumber() async throws {
        let sidebar = await sidebar(labels: [label("L1", "Receipts")], style: .sidebar)
        let before = sidebar.numberedRows.rows.map(\.title)
        #expect(before.contains("Receipts"))
        let section = try #require(
            sidebar.groups.first { $0.items.contains { $0.title == "Receipts" } }?.section)
        sidebar.fold(.header(section), folded: true)
        let after = sidebar.numberedRows.rows.map(\.title)
        #expect(!after.contains("Receipts"), "a folded section's rows are out of sight")
        #expect(after.starts(with: before.prefix { $0 != "Receipts" }), "the rows above it keep their numbers")
        sidebar.fold(.header(section), folded: false)
        #expect(sidebar.numberedRows.rows.map(\.title) == before)
    }

    @Test func theListOfMailboxesNumbersEverySectionWhateverASidebarFolded() async throws {
        // Two windows over the same store: one with a sidebar, one narrow, with the list of mailboxes.
        let sidebar = await sidebar(labels: [label("L1", "Receipts")], style: .sidebar)
        let list = await self.sidebar(labels: [label("L1", "Receipts")])
        let section = try #require(
            sidebar.groups.first { $0.items.contains { $0.title == "Receipts" } }?.section)

        sidebar.fold(.header(section), folded: true)

        #expect(!sidebar.numberedRows.rows.map(\.title).contains("Receipts"))
        #expect(list.numberedRows.rows.map(\.title).contains("Receipts"), "the list's sections don't fold")
    }

    @Test func goToOpensTheRowUnderItsName() async {
        var routes: [Route] = []
        let sidebar = await sidebar(routes: { routes.append($0) })
        guard case .ready(let perform, let title, _) = sidebar.answer(toOpening: .goTo(2)) else {
            Issue.record("Go To 2 should be ready")
            return
        }
        #expect(title == "Starred")
        perform()
        #expect(routes == [.mailbox(.starred)])
    }

    @Test func aNumberPastTheLastRowAnswersNothingSoItsItemHides() async {
        let sidebar = await sidebar()
        guard case .notHere = sidebar.answer(toOpening: .goTo(9)) else {
            Issue.record("row 9 doesn't exist")
            return
        }
        guard case .notHere = sidebar.answer(toMoving: dragged(), to: .moveTo(9)) else {
            Issue.record("row 9 doesn't exist")
            return
        }
    }

    @Test func moveToIsReadyWhereTheRowTakesTheConversationsAndNamesTheRow() async {
        let sidebar = await sidebar()
        guard case .ready(_, let title, _) = sidebar.answer(toMoving: dragged(), to: .moveTo(7)) else {
            Issue.record("Trash takes a conversation from the Inbox")
            return
        }
        #expect(title == "Trash")
    }

    @Test func moveToDimsWhereTheRowRefusesTheDropOrNothingIsPicked() async {
        let sidebar = await sidebar()
        // Starred takes no drop, and the Inbox is where the conversation already is.
        for number in [1, 2] {
            guard case .refused(let title) = sidebar.answer(toMoving: dragged(), to: .moveTo(number)) else {
                Issue.record("row \(number) should refuse")
                return
            }
            #expect(!title.isEmpty)
        }
        guard case .refused(let title) = sidebar.answer(toMoving: [], to: .moveTo(7)) else {
            Issue.record("nothing picked")
            return
        }
        #expect(title == "Trash")
    }

    @Test func amongSeveralAccountsEachInboxIsNumberedAndNamedWithItsAccount() async {
        let sidebar = await sidebar(accounts: [account, work])
        // An account's own Starred, Trash and the rest take no number: the blended rows above reach them.
        #expect(
            sidebar.numberedRows.rows.map(\.title).suffix(2) == ["Inbox (\(account.title))", "Inbox (\(work.title))"])
    }
}
