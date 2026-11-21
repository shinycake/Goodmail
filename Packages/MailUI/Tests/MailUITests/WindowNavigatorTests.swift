import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

/// The navigator finds a conversation in the list on show when it can, in the store otherwise, and keeps only the
/// answer the navigation still waits for; it tells VoiceOver of the readers the window put on show by itself.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WindowNavigatorTests {
    private nonisolated static let account = AccountID(rawValue: "a")
    private nonisolated static func id(_ name: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: account, threadID: name)
    }

    private nonisolated static func row(_ id: ThreadSummary.ID) -> ThreadSummary {
        ThreadSummary(
            id: id, subject: id.threadID, snippet: "", sender: Contact(name: nil, address: "x@example.com"),
            date: .now, isUnread: false, messageCount: 1, labelIDs: [SystemLabel.inbox])
    }

    /// A list holding `rows`.
    private final class Listed: UIViewController, ThreadSequence {
        let rows: [ThreadSummary]
        var marked: ThreadSummary.ID?

        init(_ rows: [ThreadSummary]) {
            self.rows = rows
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

        var frontRows: [ThreadSummary.ID] { rows.map(\.id) }
        var frontMailbox: Mailbox { .inbox }
        var pointerPick: [ThreadSummary.ID] { [] }
        func summary(of thread: ThreadSummary.ID) -> ThreadSummary? { rows.first { $0.id == thread } }
        func mark(reading thread: ThreadSummary.ID?) { marked = thread }
    }

    /// The store, which answers a conversation held back only once let go.
    private actor Store {
        private(set) var asked: [ThreadSummary.ID] = []
        private var holding: Set<ThreadSummary.ID>
        private var held: [ThreadSummary.ID: CheckedContinuation<Void, Never>] = [:]

        init(holding: Set<ThreadSummary.ID> = []) {
            self.holding = holding
        }

        func row(_ id: ThreadSummary.ID) async -> ThreadSummary? {
            asked.append(id)
            if holding.contains(id) { await withCheckedContinuation { held[id] = $0 } }
            return WindowNavigatorTests.row(id)
        }

        func isHolding(_ id: ThreadSummary.ID) -> Bool { held[id] != nil }

        func letGo(_ id: ThreadSummary.ID) {
            holding.remove(id)
            held.removeValue(forKey: id)?.resume()
        }
    }

    private let listed = [id("a"), id("b"), id("c")].map(row)

    private func navigator(store: Store) -> WindowNavigator {
        let navigator = WindowNavigator(
            showing: WindowState(), checking: .saved, context: { WindowNavigation.Context(arrangement: .stack) },
            lookUp: { await store.row($0) })
        let split = MailSplitViewController(
            actions: MailActions(commands: MailCommands(store: NoStore(), replay: { _ in })))
        navigator.show(
            in: split,
            making: MailScreens.Makers(
                mailboxes: { style in
                    MailboxesViewController(
                        viewModel: MailboxesViewModel(accounts: [], directory: { AsyncThrowingStream { $0.finish() } }),
                        style: style)
                },
                list: { [listed] _ in Listed(listed) },
                reader: { reading, row in Self.reader(for: row ?? Self.row(reading.thread), in: reading.mailbox) }))
        return navigator
    }

    private static func reader(for row: ThreadSummary, in mailbox: Mailbox) -> ThreadViewController {
        let model = ThreadViewModel(
            thread: row, mailbox: mailbox, accountEmail: "me@example.com", accountColor: .blue,
            messages: { AsyncThrowingStream { $0.finish() } }, load: {}, attachmentData: { _, _ in Data() },
            source: { _ in Data() })
        return ThreadViewController(viewModel: model, openURL: { _ in })
    }

    private func reads(_ navigator: WindowNavigator, _ name: String) async -> Bool {
        while navigator.state.reading?.thread != Self.id(name) {
            guard !Task.isCancelled else { return false }
            await Task.yield()
        }
        return true
    }

    @Test func aConversationTheListHoldsOpensAtOnce() async {
        let store = Store()
        let navigator = navigator(store: store)
        navigator.send(.route(.thread(Self.id("b"), in: .inbox)))
        #expect(navigator.state.reading == Reading(Self.id("b"), in: .inbox), "without waiting")
        #expect(navigator.navigation.foundRow == listed[1])
        #expect(await store.asked.isEmpty, "the store isn't read")
        #expect((navigator.screens?.front as? Listed)?.marked == Self.id("b"))
    }

    @Test func aConversationTheListDoesntHoldIsReadFromTheStore() async {
        let store = Store()
        let navigator = navigator(store: store)
        navigator.send(.route(.thread(Self.id("z"), in: .allMail)))
        #expect(navigator.state.reading == nil)
        #expect(await reads(navigator, "z"))
        #expect(navigator.state.reading?.mailbox == .allMail)
        #expect(await store.asked == [Self.id("z")])
    }

    @Test func aNewerLookupReplacesTheOneUnderWay() async {
        let store = Store(holding: [Self.id("y")])
        let navigator = navigator(store: store)
        navigator.send(.route(.thread(Self.id("y"), in: .inbox)))
        while await !store.isHolding(Self.id("y")) { await Task.yield() }
        navigator.send(.route(.thread(Self.id("z"), in: .inbox)))
        #expect(await reads(navigator, "z"))
        await store.letGo(Self.id("y"))
        for _ in 0..<50 { await Task.yield() }
        #expect(navigator.state.reading?.thread == Self.id("z"), "the older answer opens nothing")
    }

    @Test func backBeforeTheAnswerDropsIt() async {
        let store = Store(holding: [Self.id("y")])
        let navigator = navigator(store: store)
        navigator.send(.route(.thread(Self.id("y"), in: .inbox)))
        while await !store.isHolding(Self.id("y")) { await Task.yield() }
        navigator.send(.back(to: .mailboxes))
        await store.letGo(Self.id("y"))
        for _ in 0..<50 { await Task.yield() }
        #expect(navigator.state == WindowState(place: .mailboxes))
    }

    @Test func onlyAReaderTheWindowPutThereItselfIsAnnounced() throws {
        let navigator = navigator(store: Store())
        navigator.send(.route(.thread(Self.id("a"), in: .inbox)))
        let tapped = try #require(navigator.screens?.reader)
        #expect(!tapped.announcesOnAppear, "a tap, which UIKit announces as a push")
        let reader = WindowNavigation.Reader(listed[0], mailbox: .inbox, labels: [SystemLabel.inbox])
        navigator.send(
            .changed(
                MailChange(.action(.archive), on: [Self.id("a")]), reader: reader,
                front: navigator.screens?.front?.navigationFront))
        let next = try #require(navigator.screens?.reader)
        #expect(next.viewModel.thread.id == Self.id("b"))
        #expect(next.announcesOnAppear, "after Archive, VoiceOver goes to the next")
    }
}
