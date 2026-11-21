import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

/// The viewer's screens show what the navigation says in one change each, keeping a screen whose entry is unchanged,
/// so the list keeps its scroll and the reader its place (R1, R12), and report Back on the stack to it.
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

    private func screens(_ state: WindowState, made: Made = Made()) -> MailScreens {
        let split = MailSplitViewController(
            actions: MailActions(commands: MailCommands(store: NoStore(), replay: { _ in })))
        return MailScreens(
            state, row: nil, in: split, arrangement: .stack,
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
                reader: { reading, _ in
                    made.readers += 1
                    return Self.reader(for: reading)
                }))
    }

    private static func reader(for reading: Reading) -> ThreadViewController {
        let model = ThreadViewModel(
            thread: ThreadSummary(
                id: reading.thread, subject: reading.thread.threadID, snippet: "",
                sender: Contact(name: nil, address: "x@example.com"), date: .now, isUnread: false, messageCount: 1,
                labelIDs: [SystemLabel.inbox]),
            mailbox: reading.mailbox, accountEmail: "me@example.com", accountColor: .blue,
            messages: { AsyncThrowingStream { $0.finish() } }, load: {}, attachmentData: { _, _ in Data() },
            source: { _ in Data() })
        return ThreadViewController(viewModel: model, openURL: { _ in })
    }

    private func stack(of screens: MailScreens) throws -> UINavigationController {
        try #require(screens.split.viewController(for: .compact) as? UINavigationController)
    }

    private func detail(of screens: MailScreens) throws -> UINavigationController {
        try #require(screens.split.viewController(for: .secondary) as? UINavigationController)
    }

    @Test(arguments: [WindowNavigation.Arrangement.stack, .columns])
    func anUnchangedEntryKeepsItsScreen(arrangement: WindowNavigation.Arrangement) throws {
        let made = Made()
        let state = WindowState(place: .list(reading: a))
        let screens = screens(state, made: made)
        let stackBefore = try stack(of: screens).viewControllers
        let detailBefore = try detail(of: screens).viewControllers
        var filtered = state
        filtered.filter = .on([.unread])
        filtered.category = .social
        screens.show(filtered, row: nil, .quiet, in: arrangement)
        #expect(made.lists == 2 && made.readers == 2, "one of each per arrangement, made once")
        #expect(try stack(of: screens).viewControllers.elementsEqual(stackBefore, by: ===))
        #expect(try detail(of: screens).viewControllers.elementsEqual(detailBefore, by: ===))
    }

    @Test func aNewReadingTakesTheReadersPlaceOnTheStack() throws {
        let screens = screens(WindowState(place: .list(reading: a)))
        let before = try stack(of: screens).viewControllers
        screens.show(WindowState(place: .list(reading: b)), row: nil, .quiet, in: .stack)
        let after = try stack(of: screens).viewControllers
        #expect(after.count == 3, "never list › reader › reader")
        #expect(after[0] === before[0] && after[1] === before[1], "the mailboxes and the list stay")
        #expect((after[2] as? ThreadViewController)?.viewModel.thread.id == b.thread)
    }

    @Test func aNewReadingTakesTheReadersPlaceBesideTheList() throws {
        let made = Made()
        let screens = screens(WindowState(place: .list(reading: a)), made: made)
        screens.show(WindowState(place: .list(reading: b)), row: nil, .quiet, in: .columns)
        let detail = try detail(of: screens).viewControllers
        #expect(detail.count == 1)
        #expect((detail.first as? ThreadViewController)?.viewModel.thread.id == b.thread)
        #expect(made.lists == 2, "the list beside it stays")
        screens.show(WindowState(), row: nil, .quiet, in: .columns)
        #expect(try self.detail(of: screens).topViewController is NoThreadViewController)
    }

    @Test func anotherListReplacesTheListAndClosesNothingItDoesNotSay() throws {
        let screens = screens(WindowState(place: .list(reading: a)))
        let before = try stack(of: screens).viewControllers
        screens.show(WindowState(list: .mailbox(.starred)), row: nil, .quiet, in: .stack)
        let after = try stack(of: screens).viewControllers
        #expect(after.count == 2)
        #expect(after[0] === before[0] && after[1] !== before[1])
    }

    @Test func aChangeOnShowRemakesTheOtherArrangementWhenItShows() throws {
        let made = Made()
        let screens = screens(WindowState(), made: made)
        let listBeside = screens.split.viewController(for: .supplementary) as? UINavigationController
        let besideBefore = listBeside?.viewControllers.first
        var social = WindowState()
        social.category = .social
        screens.show(social, row: nil, .quiet, in: .stack)
        #expect(made.lists == 2, "the list on show stays, though its category changed")
        screens.show(social, row: nil, .resized, in: .columns)
        #expect(made.lists == 3, "the one beside was made for the category before")
        #expect(listBeside?.viewControllers.first !== besideBefore)
        screens.show(social, row: nil, .resized, in: .stack)
        screens.show(social, row: nil, .resized, in: .columns)
        #expect(made.lists == 3, "a width change alone keeps both")
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
        screens.show(WindowState(), row: nil, .quiet, in: .stack)
        let stack = try stack(of: screens)
        screens.navigationController(stack, didShow: try #require(stack.topViewController), animated: true)
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
        #expect(!screens.show(WindowState(place: .list(reading: a)), row: nil, .quiet, in: .stack))
        #expect(screens.show(WindowState(), row: nil, .quiet, in: .stack))
    }
}
