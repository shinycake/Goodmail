import Foundation
import MailCore
import Testing

@testable import MailUI

/// Dragging the accounts in Settings into a new order, which the rest of the app follows once it is stored.
@MainActor
struct AccountOrderTests {
    private let home = Account(
        id: AccountID(rawValue: "home"), email: "home@example.com", color: .blue, service: .gmail)
    private let work = Account(
        id: AccountID(rawValue: "work"), email: "work@example.com", color: .orange, service: .gmail)
    private let school = Account(
        id: AccountID(rawValue: "school"), email: "school@example.com", color: .green, service: .icloud)

    /// A model over `stored`, which records each order it is asked to store.
    @MainActor private final class Store {
        var accounts: [Account]
        var orders: [[AccountID]] = []

        init(_ accounts: [Account]) { self.accounts = accounts }

        func model() -> SettingsViewModel {
            SettingsViewModel(
                accounts: { self.accounts }, signIn: { _ in true }, remove: { _, _ in },
                update: { account in self.accounts = self.accounts.map { $0.id == account.id ? account : $0 } },
                reorder: { order in
                    try await Task.sleep(for: .milliseconds(20))
                    self.orders.append(order)
                    self.accounts = order.compactMap { id in self.accounts.first { $0.id == id } }
                },
                closed: {})
        }
    }

    @Test func aDragIsShownAtOnceAndStored() async {
        let store = Store([home, work, school])
        let model = store.model()

        // Dragging School to the top.
        model.moveAccounts(from: [2], to: 0)
        #expect(model.accounts == [school, home, work])
        await model.settled()

        #expect(store.orders == [[school.id, home.id, work.id]])
        #expect(model.accounts == [school, home, work])
    }

    @Test func droppingAnAccountWhereItWasStoresNothing() async {
        let store = Store([home, work])
        let model = store.model()

        model.moveAccounts(from: [0], to: 1)
        await model.settled()

        #expect(store.orders.isEmpty)
    }

    @Test(arguments: [
        (step: -1, order: ["work", "home", "school"]),
        (step: 1, order: ["home", "school", "work"]),
    ])
    func voiceOverMovesAnAccountOnePlace(step: Int, order: [String]) async {
        let store = Store([home, work, school])
        let model = store.model()

        model.moveAccount(work.id, by: step)
        await model.settled()

        #expect(store.accounts.map(\.id.rawValue) == order)
    }

    @Test func movingPastEitherEndDoesNothing() async {
        let store = Store([home, work])
        let model = store.model()

        model.moveAccount(home.id, by: -1)
        model.moveAccount(work.id, by: 1)
        await model.settled()

        #expect(store.orders.isEmpty)
        #expect(model.accounts == [home, work])
    }

    @Test func aRenameWhileTheOrderIsStoredKeepsBoth() async {
        let store = Store([home, work])
        let model = store.model()

        model.moveAccounts(from: [1], to: 0)
        model.rename(home.id, to: "Home")
        #expect(model.accounts.map(\.id) == [work.id, home.id], "both shown while they wait")
        #expect(model.accounts.last?.name == "Home")
        await model.settled()

        #expect(store.accounts.map(\.id) == [work.id, home.id])
        #expect(store.accounts.last?.name == "Home")
    }

    @Test func aFailedReorderIsShownAndTheAccountsReadBackAsStored() async {
        struct Refused: Error {}
        let model = SettingsViewModel(
            accounts: { [home, work] }, signIn: { _ in true }, remove: { _, _ in }, update: { _ in },
            reorder: { _ in throw Refused() }, closed: {})

        model.moveAccounts(from: [1], to: 0)
        await model.settled()

        #expect(model.error is Refused)
        #expect(model.accounts == [home, work])
    }
}
