import Foundation
import MailCore
import Testing

@testable import MailUI

/// The reader feels each action they take, as a tap that matches what it did, and nothing for what the app does by
/// itself.
@MainActor
struct HapticTests {
    private let thread = ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: "t1")

    private func actions(playing played: @escaping (Haptic) -> Void) -> MailActions {
        let actions = MailActions(commands: MailCommands(store: NoStore(), replay: { _ in }))
        actions.feedback = played
        return actions
    }

    @Test(arguments: [
        (ThreadAction.archive, Haptic.putAway), (.trash, .putAway), (.reportSpam, .putAway), (.mute, .putAway),
        (.deleteForever, .deleteForever), (.star(true), .change), (.star(false), .change), (.markRead(true), .change),
        (.markRead(false), .change), (.untrash, .change), (.moveToInbox, .change), (.unmute, .change),
        (.modifyLabels(add: ["Label_1"], remove: []), .change),
    ])
    func eachActionHasTheTapThatMatchesIt(action: ThreadAction, haptic: Haptic) {
        #expect(Haptic.performing(action) == haptic)
    }

    @Test func takingAnActionPlaysItsTapAtOnce() {
        var played: [Haptic] = []
        let actions = actions { played.append($0) }

        actions.perform(.archive, on: [thread])
        actions.perform(.star(true), on: [thread])
        actions.perform(.deleteForever, on: [thread])

        #expect(played == [.putAway, .change, .deleteForever])
    }

    @Test func movingAndSnoozingPutTheThreadAway() {
        var played: [Haptic] = []
        let actions = actions { played.append($0) }

        actions.move([thread], to: .archive, named: "Archive", from: .inbox)
        actions.snooze([thread], until: .now.addingTimeInterval(3600))
        actions.unsnooze([thread])

        #expect(played == [.putAway, .putAway, .change])
    }

    @Test(arguments: [SendTime.now, .at(.now.addingTimeInterval(3600))])
    func sendingConfirmsTheMessageWent(at time: SendTime) {
        var played: [Haptic] = []
        let actions = actions { played.append($0) }

        actions.send(Draft(accountID: AccountID(rawValue: "a1")), at: time)

        #expect(played == [.sent])
    }

    @Test func openingAThreadReadsItWithoutATap() async {
        var played: [Haptic] = []
        let actions = actions { played.append($0) }

        actions.markOpened([thread])
        await actions.settled()

        #expect(played.isEmpty)
    }

    @Test func undoingNothingPlaysNothing() async {
        var played: [Haptic] = []
        let actions = actions { played.append($0) }

        actions.undoLast()
        await actions.settled()

        #expect(played.isEmpty)
    }
}
