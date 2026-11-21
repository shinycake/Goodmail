import MailCore
import Testing

/// Which of the reader's own changes move the reader off the conversation, wherever it is read (R7, R8).
struct ReaderExitTests {
    private static let label = Mailbox(labelID: "Label_1")

    /// Where a conversation is read, with the labels it carries there.
    private static let places: [(Mailbox, Set<String>)] = [
        (.inbox, [SystemLabel.inbox]),
        (.allMail, ["Label_1"]),
        (label, [SystemLabel.inbox, "Label_1"]),
        (.trash, [SystemLabel.trash]),
        (.spam, [SystemLabel.spam]),
        (.starred, [SystemLabel.inbox, SystemLabel.starred]),
    ]

    private static let puttingAway: [MailChange.Request] = [
        .action(.archive), .action(.trash), .action(.deleteForever), .action(.reportSpam), .action(.mute),
        .snooze, .block, .move(.label("Label_2"), from: .inbox), .move(.archive, from: .allMail),
    ]

    @Test(arguments: puttingAway, places)
    func puttingAwayLeavesWhereverItIsRead(request: MailChange.Request, place: (Mailbox, Set<String>)) {
        #expect(ReaderExit.exit(after: request, labels: place.1, readIn: place.0) == .putAway)
    }

    @Test(arguments: [ThreadAction.markRead(true), .star(true), .star(false)], places)
    func marksNeverMoveTheReader(action: ThreadAction, place: (Mailbox, Set<String>)) {
        #expect(ReaderExit.exit(after: .action(action), labels: place.1, readIn: place.0) == .stays)
    }

    @Test(arguments: places)
    func markAsUnreadSetsItAsideForTheList(place: (Mailbox, Set<String>)) {
        #expect(ReaderExit.exit(after: .action(.markRead(false)), labels: place.1, readIn: place.0) == .setAside)
    }

    @Test func unstarringInStarredLeavesTheReaderOnIt() {
        let starred: Set<String> = [SystemLabel.starred]
        #expect(ReaderExit.exit(after: .action(.star(false)), labels: starred, readIn: .starred) == .stays)
    }

    @Test func aLabelChangePutsItAwayOnlyWhenItTakesItOutOfWhereItIsRead() {
        let labels: Set<String> = [SystemLabel.inbox, "Label_1"]
        let removing = MailChange.Request.action(.modifyLabels(add: [], remove: ["Label_1"]))
        #expect(ReaderExit.exit(after: removing, labels: labels, readIn: Self.label) == .putAway)
        #expect(ReaderExit.exit(after: removing, labels: labels, readIn: .inbox) == .stays)
        #expect(ReaderExit.exit(after: removing, labels: labels, readIn: .allMail) == .stays)
        let adding = MailChange.Request.action(.modifyLabels(add: ["Label_2"], remove: []))
        #expect(ReaderExit.exit(after: adding, labels: labels, readIn: Self.label) == .stays)
    }

    @Test func aChangeToOneAlreadyGoneFromWhereItIsReadDoesntMoveTheReader() {
        // Another device took the label off while it was open; adding another doesn't take it out again.
        let adding = MailChange.Request.action(.modifyLabels(add: ["Label_2"], remove: []))
        #expect(ReaderExit.exit(after: adding, labels: [SystemLabel.inbox], readIn: Self.label) == .stays)
    }

    @Test func takingItOutOfTrashOrSpamPutsItAway() {
        #expect(ReaderExit.exit(after: .action(.untrash), labels: [SystemLabel.trash], readIn: .trash) == .putAway)
        #expect(
            ReaderExit.exit(after: .action(.moveToInbox), labels: [SystemLabel.spam], readIn: .spam) == .putAway)
    }

    @Test func unsnoozingLeavesTheReaderOnIt() {
        #expect(ReaderExit.exit(after: .unsnooze, labels: [], readIn: .allMail) == .stays)
    }

    @Test func onlyLabelChangesDependOnWhereItIsRead() {
        #expect(ReaderExit.exit(after: .action(.archive)) == .putAway)
        #expect(ReaderExit.exit(after: .action(.markRead(false))) == .setAside)
        #expect(ReaderExit.exit(after: .action(.star(true))) == .stays)
        #expect(ReaderExit.exit(after: .action(.modifyLabels(add: [], remove: ["Label_1"]))) == nil)
    }
}
