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
        let actions: [ThreadAction] = [.archive, .trash, .reportSpam, .markRead(false), .star(true), .moveToInbox]
        for action in actions {
            for labels: Set<String> in [["INBOX", "UNREAD"], ["Label_1", "STARRED"], ["SPAM"], ["TRASH", "INBOX"]] {
                let restored = action.inverse(given: labels).reduce(action.applied(to: labels)) { $1.applied(to: $0) }
                #expect(restored == labels, "\(action) on \(labels)")
            }
        }
    }
}
