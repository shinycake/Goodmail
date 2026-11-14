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
            thread: thread([SystemLabel.inbox], unread: true), in: .inbox, service: .gmail, opensWindows: false)
        #expect(
            menu.sections == [
                [.answer(.reply), .answer(.replyAll), .answer(.forward)],
                [.perform(.markRead(true)), .perform(.star(true)), .perform(.mute)],
                [.snooze, .move, .changeLabels],
                [.perform(.archive), .perform(.reportSpam), .perform(.trash)],
            ])
    }

    @Test func togglesFollowTheThread() {
        let menu = ThreadMenu(
            thread: thread([SystemLabel.inbox, SystemLabel.starred, SystemLabel.muted]), in: .inbox, service: .gmail,
            opensWindows: false)
        #expect(menu.sections[1] == [.perform(.markRead(false)), .perform(.star(false)), .perform(.unmute)])
    }

    @Test func muteIsOnlyForServicesThatHaveIt() {
        let menu = ThreadMenu(thread: thread([SystemLabel.inbox]), in: .inbox, service: .icloud, opensWindows: false)
        #expect(menu.sections[1] == [.perform(.markRead(false)), .perform(.star(true))])
    }

    @Test func onlyInboxThreadsSnooze() {
        let menu = ThreadMenu(thread: thread([]), in: .allMail, service: .gmail, opensWindows: false)
        #expect(menu.sections[2] == [.move, .changeLabels])
        #expect(menu.sections[3] == [.perform(.reportSpam), .perform(.trash)], "no Archive outside the Inbox")
    }

    @Test func spamOffersTheWayBackAndTrash() {
        let menu = ThreadMenu(thread: thread([SystemLabel.spam]), in: .spam, service: .gmail, opensWindows: false)
        #expect(menu.sections[3] == [.perform(.moveToInbox), .perform(.trash)])
    }

    @Test func trashOnlyMovesOut() {
        let menu = ThreadMenu(thread: thread([SystemLabel.trash]), in: .trash, service: .gmail, opensWindows: false)
        #expect(menu.sections[3] == [.perform(.untrash), .perform(.deleteForever)])
    }

    @Test func draftsAreFinishedNotAnswered() {
        let menu = ThreadMenu(thread: thread([SystemLabel.draft]), in: .drafts, service: .gmail, opensWindows: false)
        #expect(!menu.sections.contains { $0.contains(.answer(.reply)) })
    }

    @Test func devicesWithWindowsOpenOneAfterTheAnswers() {
        let menu = ThreadMenu(thread: thread([SystemLabel.inbox]), in: .inbox, service: nil, opensWindows: true)
        #expect(menu.sections == [[.answer(.reply), .answer(.replyAll), .answer(.forward)], [.openInNewWindow]])
    }

    @Test func aListThatCannotActOnlyAnswers() {
        let menu = ThreadMenu(thread: thread([SystemLabel.inbox]), in: .inbox, service: nil, opensWindows: false)
        #expect(menu.sections == [[.answer(.reply), .answer(.replyAll), .answer(.forward)]])
    }
}
