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
        await offer.addChosen()

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
        let first = Task { await offer.addChosen() }
        while !offer.isAdding { await Task.yield() }

        await offer.addChosen()
        #expect(!offer.isFinished, "the ignored tap doesn't close the offer before anything was added")

        open.yield()
        await first.value
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

        await offer.addChosen()

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

        await choices.setSyncs(false)
        #expect(mode == .off)
        #expect(!choices.syncs)

        await choices.setSyncs(true)
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

        await choices.add(work.id)

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

        await choices.add(work.id)
        #expect(choices.failure is Refused)
        #expect(!choices.isBusy)

        choices.dismissFailure()
        #expect(choices.failure == nil)
        await choices.add(work.id)
        #expect(adds == 2)
    }
}
