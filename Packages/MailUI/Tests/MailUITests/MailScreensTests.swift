import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

/// The viewer's screens show what the navigation says in one change each, keeping a screen whose entry is unchanged,
/// so the list keeps its scroll and the reader its place (R1, R12); the one list and the one reader move between the
/// columns and the stack as the window changes width (D8); and Back on the stack is reported to the navigation.
@MainActor
struct MailScreensTests {
    private let account = AccountID(rawValue: "a")
    private var a: Reading { Reading(ThreadSummary.ID(accountID: account, threadID: "a"), in: .inbox) }
    private var b: Reading { Reading(ThreadSummary.ID(accountID: account, threadID: "b"), in: .inbox) }

    /// Screens for `state`, counting what they make.
    private final class Made {
        var lists = 0
        var readers = 0
    }

    private func screens(
        _ state: WindowState, in arrangement: WindowNavigation.Arrangement = .stack, made: Made = Made()
    ) -> MailScreens {
        let split = MailSplitViewController(
            actions: MailActions(commands: MailCommands(store: NoStore(), replay: { _ in })))
        return MailScreens(
            state, row: state.reading.map(Self.row), in: split, arrangement: arrangement,
            making: MailScreens.Makers(
                mailboxes: { style in
                    MailboxesViewController(
                        viewModel: MailboxesViewModel(accounts: [], directory: { AsyncThrowingStream { $0.finish() } }),
                        style: style)
                },
                list: { _ in
                    made.lists += 1
                    return UIViewController()
                },
                reader: { reading, row in
                    made.readers += 1
                    return Self.reader(for: row, in: reading.mailbox)
                }))
    }

    private static func row(_ reading: Reading) -> ThreadSummary {
        ThreadSummary(
            id: reading.thread, subject: reading.thread.threadID, snippet: "",
            sender: Contact(name: nil, address: "x@example.com"), date: .now, isUnread: false, messageCount: 1,
            labelIDs: [SystemLabel.inbox])
    }

    private static func reader(for row: ThreadSummary, in mailbox: Mailbox) -> ThreadViewController {
        let model = ThreadViewModel(
            thread: row, mailbox: mailbox, accountEmail: "me@example.com", accountColor: .blue,
            messages: { AsyncThrowingStream { $0.finish() } }, load: {}, attachmentData: { _, _ in Data() },
            source: { _ in Data() })
        return ThreadViewController(viewModel: model, openURL: { _ in })
    }

    /// Shows `state` with the row of what it reads.
    private func show(
        _ state: WindowState, on screens: MailScreens, _ showing: MailScreens.Showing = .quiet,
        in arrangement: WindowNavigation.Arrangement
    ) {
        screens.show(state, row: state.reading.map(Self.row), showing, in: arrangement)
    }

    private func stack(of screens: MailScreens) throws -> UINavigationController {
        try #require(screens.split.viewController(for: .compact) as? UINavigationController)
    }

    private func listBeside(_ screens: MailScreens) throws -> UINavigationController {
        try #require(screens.split.viewController(for: .supplementary) as? UINavigationController)
    }

    private func detail(of screens: MailScreens) throws -> UINavigationController {
        try #require(screens.split.viewController(for: .secondary) as? UINavigationController)
    }

    @Test(arguments: [WindowNavigation.Arrangement.stack, .columns])
    func anUnchangedEntryKeepsItsScreen(arrangement: WindowNavigation.Arrangement) throws {
        let made = Made()
        let state = WindowState(place: .list(reading: a))
        let screens = screens(state, in: arrangement, made: made)
        let list = screens.list
        let reader = screens.reader
        var filtered = state
        filtered.filter = .on([.unread])
        filtered.category = .social
        show(filtered, on: screens, in: arrangement)
        #expect(made.lists == 1 && made.readers == 1, "made once")
        #expect(screens.list === list && screens.reader === reader)
    }

    @Test func theSameListAndReaderMoveBetweenTheArrangements() throws {
        let made = Made()
        let state = WindowState(place: .list(reading: a))
        let screens = screens(state, in: .columns, made: made)
        let list = try #require(screens.list)
        let reader = try #require(screens.reader)
        #expect(try listBeside(screens).viewControllers == [list])
        #expect(try detail(of: screens).viewControllers == [reader])

        // Collapsing, as a rotation or Split View narrows the window.
        show(state, on: screens, .resized, in: .stack)
        let stacked = try stack(of: screens).viewControllers
        #expect(stacked.count == 3 && stacked[1] === list && stacked[2] === reader, "the same two, on the stack")
        #expect(try listBeside(screens).viewControllers.isEmpty, "nothing has two parents")
        #expect(screens.reader?.steps == nil, "no chevrons without steps to offer")

        // And expanding again.
        show(state, on: screens, .resized, in: .columns)
        #expect(try listBeside(screens).viewControllers == [list])
        #expect(try detail(of: screens).viewControllers == [reader])
        #expect(try stack(of: screens).viewControllers.count == 1, "the stack keeps only its mailboxes")
        #expect(made.lists == 1 && made.readers == 1, "nothing was made again")
    }

    /// On screen, a move takes the reader out of one navigation controller and into another, which UIKit reports as
    /// leaving it: the chat's attachments must go on being taken all the same.
    @Test(
        .timeLimit(.minutes(1)),
        // The package's tests run without a host app, which leaves no scene to put a window in.
        .enabled("it needs a window scene") { await MainActor.run { !UIApplication.shared.connectedScenes.isEmpty } })
    func aReaderMovedOnScreenStillTakesAttachments() async throws {
        let state = WindowState(place: .list(reading: a))
        let screens = screens(state, in: .columns)
        // A window in the test host's scene, for appearance callbacks as a real window has them.
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = screens.split
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let reader = try #require(screens.reader)
        window.layoutIfNeeded()
        #expect(reader.viewIfLoaded?.window != nil, "the reader is on screen beside the list")

        show(state, on: screens, .resized, in: .stack)
        window.layoutIfNeeded()
        show(state, on: screens, .resized, in: .columns)
        window.layoutIfNeeded()
        #expect(screens.reader === reader)

        reader.composer.picker.attach {
            DraftAttachment(filename: "scan.pdf", mimeType: "application/pdf", data: Data([1, 2, 3]))
        }
        while reader.composer.attachments.isEmpty { await Task.yield() }
        #expect(reader.composer.attachments.map(\.filename) == ["scan.pdf"])
    }

    @Test func aDroppedReaderIsLetGo() async throws {
        let screens = screens(WindowState(place: .list(reading: a)))
        let reader = try #require(screens.reader)
        show(WindowState(place: .list(reading: b)), on: screens, in: .stack)
        reader.composer.picker.attach {
            DraftAttachment(filename: "late.pdf", mimeType: "application/pdf", data: Data([1]))
        }
        for _ in 0..<50 { await Task.yield() }
        #expect(reader.composer.attachments.isEmpty, "what it was preparing has nowhere to go")
    }

    @Test func aChangeWhileNarrowMovesWithTheScreensWhenTheWindowWidens() throws {
        let made = Made()
        let screens = screens(WindowState(), made: made)
        var social = WindowState()
        social.category = .social
        show(social, on: screens, in: .stack)
        show(social, on: screens, .resized, in: .columns)
        #expect(made.lists == 1, "the one list, whatever its category")
        show(WindowState(list: .mailbox(.starred)), on: screens, in: .columns)
        #expect(made.lists == 2, "another list is another screen")
    }

    @Test func aNewReadingTakesTheReadersPlaceOnTheStack() throws {
        let screens = screens(WindowState(place: .list(reading: a)))
        let before = try stack(of: screens).viewControllers
        show(WindowState(place: .list(reading: b)), on: screens, in: .stack)
        let after = try stack(of: screens).viewControllers
        #expect(after.count == 3, "never list › reader › reader")
        #expect(after[0] === before[0] && after[1] === before[1], "the mailboxes and the list stay")
        #expect((after[2] as? ThreadViewController)?.viewModel.thread.id == b.thread)
    }

    @Test func aNewReadingTakesTheReadersPlaceBesideTheList() throws {
        let made = Made()
        let screens = screens(WindowState(place: .list(reading: a)), in: .columns, made: made)
        show(WindowState(place: .list(reading: b)), on: screens, in: .columns)
        let detail = try detail(of: screens).viewControllers
        #expect(detail.count == 1)
        #expect((detail.first as? ThreadViewController)?.viewModel.thread.id == b.thread)
        #expect(made.lists == 1, "the list beside it stays")
        show(WindowState(), on: screens, in: .columns)
        #expect(try self.detail(of: screens).topViewController is NoThreadViewController)
    }

    @Test func anotherListReplacesTheListAndClosesNothingItDoesNotSay() throws {
        let screens = screens(WindowState(place: .list(reading: a)))
        let before = try stack(of: screens).viewControllers
        show(WindowState(list: .mailbox(.starred)), on: screens, in: .stack)
        let after = try stack(of: screens).viewControllers
        #expect(after.count == 2)
        #expect(after[0] === before[0] && after[1] !== before[1])
    }

    @Test func backOnTheStackIsReported() throws {
        let screens = screens(WindowState(place: .list(reading: a)))
        var went: [WindowNavigation.Back] = []
        screens.wentBack = { went.append($0) }
        let stack = try stack(of: screens)
        let shown = stack.viewControllers
        // As the Back button pops the reader.
        stack.setViewControllers(Array(shown.prefix(2)), animated: false)
        screens.navigationController(stack, didShow: shown[1], animated: true)
        #expect(went == [.list])
        // Then back to the mailboxes.
        stack.setViewControllers([shown[0]], animated: false)
        screens.navigationController(stack, didShow: shown[0], animated: true)
        #expect(went == [.list, .mailboxes])
    }

    @Test func aChangeMadeHereIsNotReportedAsBack() throws {
        let screens = screens(WindowState(place: .list(reading: a)))
        var went: [WindowNavigation.Back] = []
        screens.wentBack = { went.append($0) }
        show(WindowState(), on: screens, in: .stack)
        let stack = try stack(of: screens)
        screens.navigationController(stack, didShow: try #require(stack.topViewController), animated: true)
        // Nor the stack giving its screens to the columns.
        show(WindowState(place: .list(reading: a)), on: screens, .resized, in: .columns)
        screens.navigationController(stack, didShow: try #require(stack.topViewController), animated: false)
        #expect(went.isEmpty)
    }

    @Test func aReaderThatCantBeMadeSaysSo() {
        let split = MailSplitViewController(
            actions: MailActions(commands: MailCommands(store: NoStore(), replay: { _ in })))
        let screens = MailScreens(
            WindowState(), row: nil, in: split, arrangement: .stack,
            making: MailScreens.Makers(
                mailboxes: {
                    MailboxesViewController(
                        viewModel: MailboxesViewModel(accounts: [], directory: { AsyncThrowingStream { $0.finish() } }),
                        style: $0)
                },
                list: { _ in UIViewController() }, reader: { _, _ in nil }))
        #expect(!screens.show(WindowState(place: .list(reading: a)), row: Self.row(a), .quiet, in: .stack))
        #expect(!screens.show(WindowState(place: .list(reading: b)), row: nil, .quiet, in: .stack), "nor without a row")
        #expect(screens.show(WindowState(), row: nil, .quiet, in: .stack))
    }
}
