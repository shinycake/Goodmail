import Foundation
import MailCore
import Testing

/// Move gives the destination's label and takes away the label of the mailbox the reader moved from.
struct MoveTests {
    private let work = Mailbox(labelID: "Label_work", accountID: AccountID(rawValue: "a"))

    private func moved(_ labels: Set<String>, to destination: MoveDestination, from mailbox: Mailbox) -> Set<String>? {
        ThreadAction.move(to: destination, from: mailbox).outcome(for: labels).labels
    }

    @Test func fromTheInbox() {
        let labels: Set<String> = ["INBOX", "UNREAD", "Label_work"]
        #expect(moved(labels, to: .label("Label_home"), from: .inbox) == ["UNREAD", "Label_work", "Label_home"])
        #expect(moved(labels, to: .archive, from: .inbox) == ["UNREAD", "Label_work"])
        #expect(moved(labels, to: .spam, from: .inbox) == ["UNREAD", "Label_work", "SPAM"])
        #expect(moved(labels, to: .trash, from: .inbox) == ["UNREAD", "Label_work", "TRASH"])
    }

    @Test func fromALabelTakesThatLabelAway() {
        let labels: Set<String> = ["INBOX", "Label_work"]
        #expect(moved(labels, to: .label("Label_home"), from: work) == ["INBOX", "Label_home"], "the Inbox stays")
        #expect(moved(labels, to: .inbox, from: work) == ["INBOX"])
        #expect(moved(labels, to: .archive, from: work) == [])
        #expect(moved(labels, to: .trash, from: work) == ["TRASH"])
        #expect(moved(["Label_work"], to: .inbox, from: work) == ["INBOX"])
    }

    @Test func outOfSpamAndTrash() {
        #expect(moved(["SPAM"], to: .inbox, from: .spam) == ["INBOX"])
        #expect(moved(["SPAM"], to: .label("Label_home"), from: .spam) == ["Label_home"])
        #expect(moved(["TRASH", "Label_work"], to: .archive, from: .trash) == ["Label_work"])
        #expect(moved(["TRASH"], to: .spam, from: .trash) == ["SPAM"])
        #expect(moved(["TRASH"], to: .inbox, from: .trash) == ["INBOX"])
    }

    @Test func fromMailboxesThatArentPlacesTheThreadLeavesTheInbox() {
        let labels: Set<String> = ["INBOX", "STARRED"]
        for mailbox in [Mailbox.starred, .sent, .drafts, .allMail] {
            #expect(moved(labels, to: .label("Label_home"), from: mailbox) == ["STARRED", "Label_home"])
            #expect(moved(labels, to: .inbox, from: mailbox) == ["INBOX", "STARRED"], "already there")
            #expect(moved(labels, to: .archive, from: mailbox) == ["STARRED"])
        }
    }

    @Test func aMoveIsOneRequestThatNeverAddsAndRemovesTheSameLabel() {
        let destinations: [MoveDestination] = [.inbox, .archive, .spam, .trash, .label("Label_work")]
        for mailbox in Mailbox.standard + [work] {
            for destination in destinations {
                guard case .modifyLabels(let add, let remove) = ThreadAction.move(to: destination, from: mailbox)
                else {
                    Issue.record("\(destination) from \(mailbox) isn't a label change")
                    continue
                }
                #expect(add.isDisjoint(with: remove))
            }
        }
    }

    @Test func undoPutsTheThreadBack() {
        let destinations: [MoveDestination] = [.inbox, .archive, .spam, .trash, .label("Label_home")]
        let cases: [(Mailbox, Set<String>)] = [
            (.inbox, ["INBOX", "UNREAD"]), (work, ["INBOX", "Label_work"]), (.spam, ["SPAM"]),
            (.trash, ["TRASH", "Label_work"]), (.starred, ["STARRED"]),
        ]
        for (mailbox, labels) in cases {
            for destination in destinations {
                let action = ThreadAction.move(to: destination, from: mailbox)
                #expect(action.undone(on: labels) == labels, "\(destination) from \(mailbox)")
            }
        }
    }

    @Test func mailboxesThatArePlaces() {
        #expect(MoveDestination(.inbox) == .inbox)
        #expect(MoveDestination(.spam) == .spam)
        #expect(MoveDestination(.trash) == .trash)
        #expect(MoveDestination(work) == .label("Label_work"))
        #expect(MoveDestination(.starred) == nil)
        #expect(MoveDestination(.allMail) == nil)
    }
}
