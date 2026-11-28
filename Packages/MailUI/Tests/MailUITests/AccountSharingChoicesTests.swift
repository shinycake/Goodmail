import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
struct AccountSharingChoicesTests {
    private let phone = Account(id: AccountID(rawValue: "p"), email: "me@gmail.com", color: .blue, service: .gmail)
    private let work = Account(id: AccountID(rawValue: "w"), email: "me@outlook.com", color: .orange, service: .outlook)
    private let home = Account(id: AccountID(rawValue: "h"), email: "me@icloud.com", color: .green, service: .icloud)

    @Test func theOfferAddsTheChosenAccountsAndDeclinesTheRest() async {
        var added: [AccountID] = []
        var declined: [AccountID] = []
        var finished = false
        let offer = SharedAccountsOffer(
            accounts: [phone, work, home],
            add: {
                added = $0
                declined = $1
            },
            decline: { _ in Issue.record("adding isn't putting it off") })
        offer.onFinished = { finished = true }
        #expect(offer.chosen == [phone.id, work.id, home.id], "every account starts chosen")

        offer.chosen.remove(work.id)
        offer.addChosen()
        await offer.settled()

        #expect(added == [phone.id, home.id], "in the offer's order")
        #expect(declined == [work.id])
        #expect(finished)
        #expect(offer.isFinished)
    }

    @Test func aSecondTapWhileAddingNeitherAddsNorFinishes() async {
        var adds = 0
        let (gate, open) = AsyncStream<Void>.makeStream()
        let offer = SharedAccountsOffer(
            accounts: [phone],
            add: { _, _ in
                adds += 1
                for await _ in gate { break }
            }, decline: { _ in })
        offer.addChosen()
        #expect(offer.isAdding, "the offer adds on its own, with no one waiting")

        offer.addChosen()
        #expect(!offer.isFinished, "the ignored tap doesn't close the offer before anything was added")

        open.yield()
        await offer.settled()
        #expect(adds == 1)
        #expect(offer.isFinished)
    }

    @Test func notNowDeclinesThemAll() {
        var declined: [AccountID] = []
        let offer = SharedAccountsOffer(accounts: [phone, work], add: { _, _ in }, decline: { declined = $0 })

        offer.notNow()

        #expect(declined == [phone.id, work.id])
        #expect(offer.isFinished)
    }

    @Test func aFailedAddKeepsTheOfferOpen() async {
        struct Refused: Error {}
        var finished = false
        let offer = SharedAccountsOffer(accounts: [phone], add: { _, _ in throw Refused() }, decline: { _ in })
        offer.onFinished = { finished = true }

        offer.addChosen()
        await offer.settled()

        #expect(offer.failure is Refused)
        #expect(!finished)
        #expect(!offer.isFinished, "the screen stays open, so the reader can try again")

        offer.dismissFailure()
        #expect(offer.failure == nil)
        guard case .choosing = offer.state else {
            Issue.record("not choosing: \(offer.state)")
            return
        }
    }

    @Test func turningSyncingOnFollowsTheOtherDevicesAndOffSharesNothing() async {
        var mode = AccountSharingMode.offering
        let choices = AccountSharingChoices(
            reload: { (mode, []) }, setMode: { mode = $0 }, add: { _ in })

        choices.setSyncs(false)
        await choices.settled()
        #expect(mode == .off)
        #expect(!choices.syncs)

        choices.setSyncs(true)
        await choices.settled()
        #expect(mode == .following)
        #expect(choices.syncs)
    }

    @Test func addingAnAccountFromElsewhereReadsTheListBackAndTellsTheScreen() async {
        var elsewhere = [work, home]
        var changed = false
        let choices = AccountSharingChoices(
            reload: { (.following, elsewhere) }, setMode: { _ in },
            add: { id in elsewhere.removeAll { $0.id == id } })
        choices.onAccountsChanged = { changed = true }

        choices.add(work.id)
        await choices.settled()

        #expect(choices.elsewhere == [home])
        #expect(changed)
        #expect(!choices.isBusy)
        #expect(choices.failure == nil)
    }

    @Test func aFailedChangeIsShownUntilDismissedAndLetsTheNextOneStart() async {
        struct Refused: Error {}
        var adds = 0
        let choices = AccountSharingChoices(
            reload: { [work] in (.following, [work]) }, setMode: { _ in },
            add: { _ in
                adds += 1
                throw Refused()
            })

        choices.add(work.id)
        await choices.settled()
        #expect(choices.failure is Refused)
        #expect(!choices.isBusy)

        choices.dismissFailure()
        #expect(choices.failure == nil)
        choices.add(work.id)
        await choices.settled()
        #expect(adds == 2)
    }

    @Test func aChangeRunsOnItsOwnAndTheOthersWaitForIt() async {
        var modes: [AccountSharingMode] = []
        let (gate, open) = AsyncStream<Void>.makeStream()
        let choices = AccountSharingChoices(
            reload: { [work] in (.following, [work]) },
            setMode: {
                modes.append($0)
                for await _ in gate { break }
            },
            add: { _ in Issue.record("an add waits for the switch under way") })

        choices.setSyncs(false)
        #expect(choices.isBusy)
        choices.add(work.id)
        choices.setSyncs(true)
        open.yield()
        await choices.settled()
        #expect(modes == [.off])
        #expect(!choices.isBusy)
    }
}
