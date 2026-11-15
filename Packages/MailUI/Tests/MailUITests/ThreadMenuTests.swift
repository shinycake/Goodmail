import Foundation
import MailCore
import Testing

@testable import MailUI

/// A row's context menu offers what the thread allows where it is: answers first, Trash last.
@MainActor
struct ThreadMenuTests {
    private func thread(_ labels: Set<String>, unread: Bool = false) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t"), subject: "Plan", snippet: "",
            sender: Contact(name: "Dana", address: "dana@example.com"), date: .now, isUnread: unread,
            messageCount: 2, labelIDs: labels)
    }

    @Test func anInboxThreadOffersEverythingGroupedAndTrashLast() {
        let menu = ThreadMenu(
            thread: thread([SystemLabel.inbox], unread: true), in: .inbox, reach: .actions(pinned: false),
            opensWindows: false)
        #expect(
            menu.sections == [
                [.answer(.reply), .answer(.replyAll), .answer(.forward)],
                [.perform(.markRead(true)), .perform(.star(true)), .pin(true), .perform(.mute)],
                [.snooze, .move, .changeLabels],
                [.perform(.archive), .perform(.reportSpam), .perform(.trash)],
            ])
    }

    @Test func togglesFollowTheThread() {
        let menu = ThreadMenu(
            thread: thread([SystemLabel.inbox, SystemLabel.starred, SystemLabel.muted]), in: .inbox,
            reach: .actions(pinned: false),
            opensWindows: false)
        #expect(
            menu.sections[1] == [.perform(.markRead(false)), .perform(.star(false)), .pin(true), .perform(.unmute)])
    }

    @Test func aPinnedThreadOffersUnpin() {
        let menu = ThreadMenu(
            thread: thread([SystemLabel.inbox]), in: .inbox, reach: .actions(pinned: true), opensWindows: false)
        #expect(menu.sections[1] == [.perform(.markRead(false)), .perform(.star(true)), .pin(false), .perform(.mute)])
    }

    @Test func aListWithoutPinsOffersNeitherPinNorUnpin() {
        let menu = ThreadMenu(
            thread: thread([SystemLabel.inbox]), in: .inbox, reach: .actions(pinned: nil), opensWindows: false)
        #expect(menu.sections[1] == [.perform(.markRead(false)), .perform(.star(true)), .perform(.mute)])
    }

    @Test func onlyInboxThreadsSnooze() {
        let menu = ThreadMenu(thread: thread([]), in: .allMail, reach: .actions(pinned: false), opensWindows: false)
        #expect(menu.sections[2] == [.move, .changeLabels])
        #expect(menu.sections[3] == [.perform(.reportSpam), .perform(.trash)], "no Archive outside the Inbox")
    }

    @Test func spamOffersTheWayBackAndTrash() {
        let menu = ThreadMenu(
            thread: thread([SystemLabel.spam]), in: .spam, reach: .actions(pinned: false), opensWindows: false)
        #expect(menu.sections[3] == [.perform(.moveToInbox), .perform(.trash)])
    }

    @Test func trashOnlyMovesOut() {
        let menu = ThreadMenu(
            thread: thread([SystemLabel.trash]), in: .trash, reach: .actions(pinned: false), opensWindows: false)
        #expect(menu.sections[3] == [.perform(.untrash), .perform(.deleteForever)])
    }

    @Test func draftsAreFinishedNotAnswered() {
        let menu = ThreadMenu(
            thread: thread([SystemLabel.draft]), in: .drafts, reach: .actions(pinned: false), opensWindows: false)
        #expect(!menu.sections.contains { $0.contains(.answer(.reply)) })
    }

    @Test func devicesWithWindowsOpenOneAfterTheAnswers() {
        let menu = ThreadMenu(thread: thread([SystemLabel.inbox]), in: .inbox, reach: .readOnly, opensWindows: true)
        #expect(menu.sections == [[.answer(.reply), .answer(.replyAll), .answer(.forward)], [.openInNewWindow]])
    }

    @Test func aListThatCannotActOnlyAnswers() {
        let menu = ThreadMenu(thread: thread([SystemLabel.inbox]), in: .inbox, reach: .readOnly, opensWindows: false)
        #expect(menu.sections == [[.answer(.reply), .answer(.replyAll), .answer(.forward)]])
    }
}
