import Foundation
import MailCore
import Testing

struct ThreadActionTests {
    @Test func actionsChangeLabelsAsGmailDoes() {
        #expect(ThreadAction.archive.applied(to: ["INBOX", "UNREAD"]) == ["UNREAD"])
        #expect(ThreadAction.trash.applied(to: ["INBOX", "Label_1"]) == ["TRASH", "Label_1"])
        #expect(ThreadAction.untrash.applied(to: ["TRASH"]) == [])
        #expect(ThreadAction.markRead(true).applied(to: ["INBOX", "UNREAD"]) == ["INBOX"])
        #expect(ThreadAction.reportSpam.applied(to: ["INBOX"]) == ["SPAM"])
    }

    @Test func undoPutsBackOnlyWhatChanged() {
        #expect(
            ThreadAction.archive.inverse(given: ["INBOX", "UNREAD"]) == [.modifyLabels(add: ["INBOX"], remove: [])])
        #expect(ThreadAction.archive.inverse(given: ["Label_1"]) == [], "archiving archived mail changes nothing")
        #expect(ThreadAction.star(true).inverse(given: []) == [.modifyLabels(add: [], remove: ["STARRED"])])
        #expect(ThreadAction.trash.inverse(given: ["INBOX"]) == [.untrash, .modifyLabels(add: ["INBOX"], remove: [])])
    }

    @Test func undoRestoresTheLabels() {
        let actions: [ThreadAction] = [
            .archive, .trash, .reportSpam, .markRead(false), .star(true), .moveToInbox, .mute, .unmute,
        ]
        for action in actions {
            for labels: Set<String> in [
                ["INBOX", "UNREAD"], ["Label_1", "STARRED"], ["SPAM"], ["TRASH", "INBOX"], ["MUTED", "STARRED"],
            ] {
                let restored = action.inverse(given: labels).reduce(action.applied(to: labels)) { $1.applied(to: $0) }
                #expect(restored == labels, "\(action) on \(labels)")
            }
        }
    }

    @Test func muteTakesTheThreadOutOfTheInboxAndUnmuteBringsItBack() {
        #expect(ThreadAction.mute.applied(to: ["INBOX", "UNREAD", "Label_1"]) == ["MUTED", "UNREAD", "Label_1"])
        #expect(ThreadAction.unmute.applied(to: ["MUTED", "Label_1"]) == ["INBOX", "Label_1"])
        #expect(ThreadAction.mute.inverse(given: ["INBOX"]) == [.modifyLabels(add: ["INBOX"], remove: ["MUTED"])])
        #expect(ThreadAction.mute.inverse(given: ["MUTED"]) == [], "muting muted mail changes nothing")
    }

    @Test func muteIsOfferedOnlyWhereItApplies() {
        #expect(ThreadAction.muting(gmail([["INBOX"]])) == .mute)
        #expect(ThreadAction.muting(gmail([["Label_1"], ["INBOX"]])) == .mute, "archived mail can be muted too")
        #expect(ThreadAction.muting(gmail([["MUTED"]])) == .unmute)
        #expect(ThreadAction.muting(gmail([["MUTED"], ["MUTED", "Label_1"]])) == .unmute)
        #expect(ThreadAction.muting(gmail([["MUTED"], ["INBOX"]])) == nil, "a mix offers neither")
        #expect(ThreadAction.muting(gmail([["INBOX"], ["SPAM"]])) == nil)
        #expect(ThreadAction.muting(gmail([["TRASH", "MUTED"]])) == nil)
        #expect(ThreadAction.muting([]) == nil)
        #expect(ThreadAction.muting([(["INBOX"], .icloud)]) == nil, "IMAP has no Mute")
        #expect(ThreadAction.muting([(["INBOX"], .gmail), (["INBOX"], .icloud)]) == nil)
    }

    private func gmail(_ threads: [Set<String>]) -> [(labels: Set<String>, service: MailService)] {
        threads.map { ($0, .gmail) }
    }
}
