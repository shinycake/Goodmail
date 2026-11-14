import Foundation
import MailCore
import Testing

struct ThreadActionTests {
    @Test func actionsChangeLabelsAsGmailDoes() {
        #expect(ThreadAction.archive.outcome(for: ["INBOX", "UNREAD"]) == .labeled(["UNREAD"]))
        #expect(ThreadAction.trash.outcome(for: ["INBOX", "Label_1"]) == .labeled(["TRASH", "Label_1"]))
        #expect(ThreadAction.untrash.outcome(for: ["TRASH"]) == .labeled([]))
        #expect(ThreadAction.markRead(true).outcome(for: ["INBOX", "UNREAD"]) == .labeled(["INBOX"]))
        #expect(ThreadAction.reportSpam.outcome(for: ["INBOX"]) == .labeled(["SPAM"]))
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
                #expect(action.undone(on: labels) == labels, "\(action) on \(labels)")
            }
        }
    }

    @Test func deleteForeverDeletesWhatIsInTrashAndLeavesTheRest() {
        #expect(ThreadAction.deleteForever.outcome(for: ["TRASH", "UNREAD"]) == .deleted)
        #expect(ThreadAction.deleteForever.outcome(for: ["INBOX", "TRASH"]) == .deleted, "a thread in Trash at all")
        #expect(ThreadAction.deleteForever.outcome(for: ["INBOX", "UNREAD"]) == .labeled(["INBOX", "UNREAD"]))
        #expect(ThreadAction.deleteForever.inverse(given: ["TRASH"]) == [], "nothing brings it back")
    }

    @Test func muteTakesTheThreadOutOfTheInboxAndUnmuteBringsItBack() {
        #expect(
            ThreadAction.mute.outcome(for: ["INBOX", "UNREAD", "Label_1"]) == .labeled(["MUTED", "UNREAD", "Label_1"]))
        #expect(ThreadAction.unmute.outcome(for: ["MUTED", "Label_1"]) == .labeled(["INBOX", "Label_1"]))
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

extension ThreadAction {
    /// The labels a thread carrying `labels` has after this action and then its undo, or `nil` if either deletes it.
    func undone(on labels: Set<String>) -> Set<String>? {
        inverse(given: labels).reduce(outcome(for: labels)) { outcome, undo in
            guard case .labeled(let labels) = outcome else { return outcome }
            return undo.outcome(for: labels)
        }.labels
    }
}

extension ThreadAction.Outcome {
    var labels: Set<String>? {
        guard case .labeled(let labels) = self else { return nil }
        return labels
    }
}
