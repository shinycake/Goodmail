import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

/// Which messages are cards: decided when the conversation first shows its messages, then the reader's.
struct OpenCardsTests {
    private let account = AccountID(rawValue: "a")

    private func message(_ id: String, unread: Bool = false) -> Message {
        Message(
            id: Message.ID(accountID: account, messageID: id), threadID: "t",
            from: Contact(name: "Dana", address: "dana@example.com"), subject: "Plan",
            date: Date(timeIntervalSince1970: 1_800_000_000), labelIDs: unread ? ["INBOX", "UNREAD"] : ["INBOX"],
            body: MessageBody(plain: id))
    }

    @Test func aConversationStoredEmptyFirstStillOpensItsCardsWhenItsMessagesCome() {
        var cards = OpenCards.unset
        cards.arrived([])
        cards.open([])
        #expect(cards == .unset)

        let messages = [message("1", unread: true), message("2"), message("3")]
        cards.arrived(messages)
        #expect(cards.ids == [messages[0].id, messages[2].id])
    }

    /// Opening marks the conversation read, and the store brings it again read, maybe before any transcript of the
    /// first arrival shows: the unread history still opens.
    @Test func theFirstArrivalDecidesThoughTheMessagesComeAgainRead() {
        let unread = [message("1", unread: true), message("2", unread: true), message("3", unread: true)]
        var cards = OpenCards.unset
        cards.arrived(unread)
        cards.arrived(unread.map { message($0.id.messageID) })
        #expect(cards.ids == Set(unread.map(\.id)))
    }

    @Test func laterMessagesKeepTheReadersChoiceAndOpenSyncedCopies() {
        let messages = [message("1"), message("2")]
        var cards = OpenCards.unset
        cards.arrived(messages)
        cards.toggle(messages[0].id)
        cards.toggle(messages[1].id)
        #expect(cards.ids == [messages[0].id])

        let copy = message("3")
        cards.arrived(messages + [copy, message("4", unread: true)])
        cards.open([copy.id])
        #expect(cards.ids == [messages[0].id, copy.id], "only the first arrival opens the unread and the newest")
    }

    @Test func theLastCardStaysOpen() {
        let only = message("1")
        var cards = OpenCards.unset
        cards.arrived([only])
        cards.toggle(only.id)
        #expect(cards.ids == [only.id])
    }
}

/// A newer transcript request overtakes the one in flight, which then shows nothing, and takes over its copies.
struct TranscriptWorkTests {
    private func id(_ name: String) -> Message.ID {
        Message.ID(accountID: AccountID(rawValue: "a"), messageID: name)
    }

    @Test func onlyTheNewestRequestShowsAndOpensTheCopiesOfThoseItOvertook() {
        var work = TranscriptWork.idle
        let older = work.start(copies: [id("copy")])
        let newer = work.start(copies: [])

        #expect(work.finish(older) == nil, "overtaken")
        #expect(work.finish(newer) == [id("copy")])
        #expect(work == .idle)
    }

    @Test func anOvertakenRequestThatEndsLastChangesNothing() {
        var work = TranscriptWork.idle
        let older = work.start(copies: [])
        let newer = work.start(copies: [id("copy")])
        #expect(work.finish(newer) == [id("copy")])

        let next = work.start(copies: [])
        #expect(work.finish(older) == nil)
        #expect(work.finish(next) == [], "the copies were opened by the request that showed them")
    }
}

/// A body's script reports count only from its own page's commit, so an older page can't size or judge newer content.
@MainActor
struct BodyLoadTests {
    private final class Navigation {}
    private struct Content: Equatable {
        var message: String
        var allowsRemoteContent: Bool
    }
    private typealias Load = BodyLoad<Content, Navigation>

    private let plain = Content(message: "m", allowsRemoteContent: false)
    private let withImages = Content(message: "m", allowsRemoteContent: true)

    /// A body shown and sized, as after its page reported its height.
    private func shown(_ content: Content) -> (Load, Navigation) {
        var load = Load.blank
        let navigation = Navigation()
        load.show(content, sameMessage: false, work: Task {})
        load.load(navigation)
        load.commit(navigation)
        _ = load.laidOut()
        return (load, navigation)
    }

    @Test func reportsCountOnlyOnceTheirPageCommits() {
        var load = Load.blank
        #expect(load.laidOut() == nil, "a spare's blank page")
        load.show(plain, sameMessage: false, work: Task {})
        #expect(load.showsPreview)
        #expect(load.laidOut() == nil, "still preparing")

        let navigation = Navigation()
        load.load(navigation)
        load.commit(Navigation())
        #expect(load.reporting == nil, "another page's commit")

        load.commit(navigation)
        #expect(load.reporting == plain)
        #expect(load.laidOut() == plain)
        #expect(!load.showsPreview)
    }

    @Test func loadingRemoteImagesKeepsTheBodyAndStopsTheOldPagesReports() {
        var (load, _) = shown(plain)
        load.show(withImages, sameMessage: true, work: Task {})
        #expect(!load.showsPreview, "the body that shows keeps its height")
        #expect(load.laidOut() == nil, "the old page's height isn't about the content with images")

        let navigation = Navigation()
        load.load(navigation)
        load.commit(navigation)
        #expect(load.laidOut() == withImages)
    }

    @Test func anotherMessageStartsFromItsWords() {
        var (load, _) = shown(plain)
        load.show(Content(message: "n", allowsRemoteContent: false), sameMessage: false, work: Task {})
        #expect(load.showsPreview)
    }

    @Test func aNewerShowCancelsTheOnePreparing() {
        var load = Load.blank
        let first = Task<Void, Never> { _ = try? await Task.sleep(for: .seconds(60)) }
        load.show(plain, sameMessage: false, work: first)
        load.show(withImages, sameMessage: true, work: Task {})
        #expect(first.isCancelled)
        #expect(load.content == withImages)
    }

    /// A load that never commits, or a page whose content process went, loads once more, keeping what shows.
    @Test func aFailedLoadLoadsOnceMore() {
        let now = ContinuousClock.now
        var (load, _) = shown(plain)
        load.show(withImages, sameMessage: true, work: Task {})
        load.load(Navigation())
        #expect(load.reloadable(at: now) == withImages)

        load.reload(work: Task {}, at: now)
        #expect(load.content == withImages)
        #expect(!load.showsPreview, "the body that shows keeps its height")
        load.load(Navigation())
        #expect(load.reloadable(at: now + .seconds(1)) == nil, "a body that keeps failing isn't loaded forever")
    }

    /// Big images can cost a page its content process each time it lays out: it reloads once, then stays, though a
    /// page lost once in a while comes back each time.
    @Test func aPageThatLosesItsProcessEachTimeItLaysOutDoesntReloadForever() {
        let start = ContinuousClock.now
        var (load, _) = shown(plain)
        #expect(load.reloadable(at: start) == plain, "a page lost once comes back")
        load.reload(work: Task {}, at: start)
        let again = Navigation()
        load.load(again)
        load.commit(again)
        #expect(load.laidOut() == plain)

        #expect(load.reloadable(at: start + .seconds(2)) == nil, "lost again right after laying out")
        load.reload(work: Task {}, at: start + .seconds(2))
        #expect(load.reporting == plain, "the page stays as it is")

        #expect(load.reloadable(at: start + Load.reloadQuiet) == plain, "much later, a page lost once comes back")
    }

    @Test func nothingReloadsWhileTheDocumentIsBeingPrepared() {
        let now = ContinuousClock.now
        var load = Load.blank
        #expect(load.reloadable(at: now) == nil)
        load.show(plain, sameMessage: false, work: Task {})
        #expect(load.reloadable(at: now) == nil, "it loads anyway")
    }
}

/// Only the attachment tapped last opens, once.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AttachmentPreviewerTests {
    private let message = Message.ID(accountID: AccountID(rawValue: "a"), messageID: "m")
    private let slow = MailCore.Attachment(id: "1", filename: "slow.pdf", mimeType: "application/pdf", size: 10)
    private let quick = MailCore.Attachment(id: "2", filename: "quick.pdf", mimeType: "application/pdf", size: 10)

    private func file(_ attachment: MailCore.Attachment) -> URL {
        URL(filePath: "/tmp/\(attachment.filename)")
    }

    /// Lets a fetch go on only once opened; cancelling the fetch doesn't, as a fetch that ignores cancellation.
    private final class Gate {
        private var waiting: [CheckedContinuation<Void, Never>] = []
        private var isOpen = false

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { waiting.append($0) }
        }

        func open() {
            isOpen = true
            for continuation in waiting { continuation.resume() }
            waiting = []
        }
    }

    @Test func aSlowAttachmentTappedFirstNeverOpensOverTheOneTappedAfter() async throws {
        let previewer = AttachmentPreviewer()
        var opened: [URL] = []
        var slowLoading: [Bool] = []
        let gate = Gate()
        let (slowDone, slowDoneSignal) = AsyncStream<Void>.makeStream()
        previewer.open(
            slow, in: message,
            file: { [slowFile = file(slow)] in
                await gate.wait()
                slowDoneSignal.yield()
                return slowFile
            }, loading: { slowLoading.append($0) },
            finished: { if case .success(let url) = $0 { opened.append(url) } })
        previewer.open(
            quick, in: message, file: { [quickFile = file(quick)] in quickFile }, loading: { _ in },
            finished: { if case .success(let url) = $0 { opened.append(url) } })
        #expect(slowLoading == [true, false], "the slow one stops showing its wait as soon as it is replaced")

        await previewer.settled()
        #expect(opened == [file(quick)])

        // The slow fetch ends after the quick one opened, and opens nothing over it.
        gate.open()
        for await _ in slowDone { break }
        await Task.yield()
        #expect(opened == [file(quick)])
        #expect(slowLoading == [true, false])
    }

    /// The attachment downloading tapped again elsewhere, as in the letter's sheet over its bubble, shows the wait
    /// there and opens once.
    @Test func aTapFromAnotherPlaceMovesTheWaitThere() async {
        let previewer = AttachmentPreviewer()
        var bubble: [Bool] = []
        var sheet: [Bool] = []
        var fetches = 0
        var opened = 0
        let gate = Gate()
        let fetch = { [quickFile = file(quick)] in
            fetches += 1
            await gate.wait()
            return quickFile
        }
        previewer.open(quick, in: message, file: fetch, loading: { bubble.append($0) }, finished: { _ in opened += 1 })
        previewer.open(quick, in: message, file: fetch, loading: { sheet.append($0) }, finished: { _ in opened += 1 })
        #expect(bubble == [true, false])
        #expect(sheet == [true])

        gate.open()
        await previewer.settled()
        #expect(sheet == [true, false])
        #expect(fetches == 1)
        #expect(opened == 1)
    }

    @Test func aDoubleTapOpensOnePreview() async {
        let previewer = AttachmentPreviewer()
        var fetches = 0
        var opened = 0
        let open = {
            previewer.open(
                self.quick, in: self.message,
                file: { [quickFile = file(quick)] in
                    fetches += 1
                    return quickFile
                }, loading: { _ in }, finished: { _ in opened += 1 })
        }
        open()
        open()
        await previewer.settled()

        #expect(fetches == 1)
        #expect(opened == 1)
    }

    @Test func aFailedDownloadSaysWhy() async {
        let previewer = AttachmentPreviewer()
        var failed = false
        previewer.open(
            quick, in: message, file: { throw ProviderError.notFound }, loading: { _ in },
            finished: { result in
                if case .failure = result { failed = true }
            })
        await previewer.settled()
        #expect(failed)
    }
}

/// The share sheet points from More while the window's toolbar holds the controls, and from Share once the bar at
/// the bottom does again.
@MainActor
struct ReaderBarsTests {
    @Test func theShareSheetFollowsTheBarsAfterAWindowLeavesTheDesktop() {
        let model = ThreadViewModel(
            thread: ThreadSummary(
                id: .init(accountID: AccountID(rawValue: "a"), threadID: "t"), subject: "Plan", snippet: "",
                sender: Contact(name: nil, address: "x@example.com"), date: .now, isUnread: false, messageCount: 1,
                labelIDs: []),
            mailbox: .inbox, accountEmail: "me@example.com", accountColor: .blue,
            messages: { AsyncThrowingStream { $0.finish() } }, load: {}, attachmentData: { _, _ in Data() },
            source: { _ in Data() })
        let reader = ThreadViewController(viewModel: model, openURL: { _ in })
        // The package's tests run without a host app, so no scene to make a window in (`UIWindow(frame:)` is
        // deprecated): the window is a parent screen whose traits the reader takes, as it does a window's.
        let window = UIViewController()
        window.traitOverrides.interactionStyle = .desktop
        window.addChild(reader)
        window.view.addSubview(reader.view)
        reader.didMove(toParent: window)
        window.updateTraitsIfNeeded()
        reader.updateTraitsIfNeeded()
        #expect(reader.traitCollection.interactionStyle == .desktop)
        #expect(reader.exportAnchor !== reader.shareItem, "More, which holds Share")

        // The window's change reaches the reader as a trait change, which lays its bars out again.
        window.traitOverrides.interactionStyle = .touch
        window.updateTraitsIfNeeded()
        reader.updateTraitsIfNeeded()
        #expect(reader.traitCollection.interactionStyle == .touch)
        #expect(reader.exportAnchor === reader.shareItem)
    }
}
