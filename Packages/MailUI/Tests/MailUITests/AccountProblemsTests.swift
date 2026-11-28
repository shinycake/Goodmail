import Foundation
import MailCore
import Testing
import UIKit

@testable import MailUI

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// A mailbox list tells of its own accounts' sync problems, and its button fixes each one.
@MainActor struct AccountProblemsTests {
    private let gmail = Account(id: AccountID(rawValue: "g"), email: "g@gmail.com", color: .teal, service: .gmail)
    private let icloud = Account(id: AccountID(rawValue: "i"), email: "i@icloud.com", color: .orange, service: .icloud)

    private func viewModel(
        _ mailbox: Mailbox = .inbox, health: AccountHealthBoard, refresh: @escaping () async throws -> Void = {},
        retryAlerts: @escaping () async -> Void = {}, navigate: @escaping (Route) -> Void = { _ in }
    ) -> MailboxViewModel {
        MailboxViewModel(
            mailbox: mailbox, accounts: [gmail, icloud], source: .flat(.whole { AsyncThrowingStream { $0.finish() } }),
            refresh: refresh, retryAlerts: retryAlerts, navigate: navigate, health: health)
    }

    @Test func aTurnedDownSignInShowsInEveryMailboxOfItsAccount() {
        let health = AccountHealthBoard()
        health.record(.failure(OAuthSession.Failure.signedOut), for: gmail.id)

        let notice = AccountProblemNotice(account: gmail, problem: .signInRejected)
        #expect(viewModel(health: health).problems == [notice])
        #expect(
            viewModel(Mailbox(labelID: SystemLabel.inbox, accountID: gmail.id), health: health).problems == [notice])
        #expect(viewModel(Mailbox(labelID: SystemLabel.inbox, accountID: icloud.id), health: health).problems.isEmpty)
    }

    @Test func aPassingFailureIsNotShown() {
        let health = AccountHealthBoard()
        health.record(.failure(URLError(.timedOut)), for: icloud.id)
        #expect(viewModel(health: health).problems.isEmpty)
    }

    @Test func aFailureThatLastsIsShownUntilASyncWorks() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let health = AccountHealthBoard(now: { now })
        health.record(.failure(URLError(.cannotFindHost)), for: icloud.id)
        now += AccountHealth.patience
        health.record(.failure(URLError(.cannotFindHost)), for: icloud.id)
        #expect(viewModel(health: health).problems.map(\.problem) == [.cantSync(.serverUnreachable)])

        health.record(.success(()), for: icloud.id)
        #expect(viewModel(health: health).problems.isEmpty)
    }

    @Test func aRemovedAccountIsForgotten() {
        let health = AccountHealthBoard()
        health.record(.failure(OAuthSession.Failure.signedOut), for: gmail.id)
        health.recordAlerts(.failure(PushRelayClient.Failure.loginRefused), for: gmail.id)
        health.forget(gmail.id)
        #expect(health.health.isEmpty)
        #expect(health.alerts.isEmpty)
    }

    @Test func alertsTheMailServerKeepsRefusingShowAsPausedUntilTheRelayTakesTheLogin() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let health = AccountHealthBoard(now: { now })
        let refused = Result<Void, any Error>.failure(PushRelayClient.Failure.loginRefused)
        health.recordAlerts(refused, for: icloud.id)
        #expect(viewModel(health: health).problems.isEmpty)

        now += AccountHealth.patience
        health.recordAlerts(refused, for: icloud.id)
        let paused = viewModel(health: health).problems
        #expect(paused == [AccountProblemNotice(account: icloud, problem: .alertsPaused)])
        #expect(paused.summary?.title == "Alerts Paused")
        #expect(paused[0].message.contains("i@icloud.com"))

        health.recordAlerts(.success(()), for: icloud.id)
        #expect(viewModel(health: health).problems.isEmpty)
    }

    @Test func anAccountThatCantSyncSaysSoBeforeItsPausedAlerts() {
        var now = Date(timeIntervalSinceReferenceDate: 0)
        let health = AccountHealthBoard(now: { now })
        health.recordAlerts(.failure(PushRelayClient.Failure.loginRefused), for: icloud.id)
        now += AccountHealth.patience
        health.recordAlerts(.failure(PushRelayClient.Failure.loginRefused), for: icloud.id)
        health.record(.failure(IMAPSignInRejected()), for: icloud.id)

        #expect(viewModel(health: health).problems.map(\.problem) == [.signInRejected])
    }

    @Test func fixingPausedAlertsRegistersWithTheRelayAgain() async {
        var retried = 0
        let model = viewModel(health: AccountHealthBoard(), retryAlerts: { retried += 1 })
        await model.fix(AccountProblemNotice(account: icloud, problem: .alertsPaused))?.value
        #expect(retried == 1)
    }

    @Test func fixingPausedAlertsAgainWhileTheyRegisterJoinsTheRegistration() async throws {
        var retried = 0
        let (gate, open) = AsyncStream<Void>.makeStream()
        let model = viewModel(
            health: AccountHealthBoard(),
            retryAlerts: {
                retried += 1
                for await _ in gate { break }
            })
        let notice = AccountProblemNotice(account: icloud, problem: .alertsPaused)
        let first = try #require(model.fix(notice))
        #expect(model.fix(notice) == first)
        open.yield()
        await first.value
        #expect(retried == 1)
    }

    @Test func fixingATurnedDownSignInOpensTheSignIn() {
        var routes: [Route] = []
        let model = viewModel(health: AccountHealthBoard(), navigate: { routes.append($0) })
        #expect(model.fix(AccountProblemNotice(account: gmail, problem: .signInRejected)) == nil)
        #expect(routes == [.signInAgain(gmail.id)])
    }

    @Test func fixingAFailingSyncSyncsNow() async {
        var refreshed = 0
        let model = viewModel(health: AccountHealthBoard(), refresh: { refreshed += 1 })
        await model.fix(AccountProblemNotice(account: icloud, problem: .cantSync(.timedOut)))?.value
        #expect(refreshed == 1)
    }

    @Test func theToolbarNamesOneProblemOrCountsThem() {
        let one = [AccountProblemNotice(account: gmail, problem: .signInRejected)]
        #expect(one.summary?.title == "Sign-In Needed")
        #expect(one.summary?.subtitle == "g@gmail.com")
        let two = one + [AccountProblemNotice(account: icloud, problem: .cantSync(.timedOut))]
        #expect(two.summary?.title == "Accounts Need Attention")
        #expect(two.summary?.subtitle == nil)
        #expect([AccountProblemNotice]().summary == nil)
    }

    @Test(arguments: [
        (MailService.gmail, "Sign In Again"), (.outlook, "Sign In Again"), (.icloud, "Update Password"),
        (.imap, "Update Password"),
    ])
    func eachServiceIsFixedItsOwnWay(service: MailService, fix: String) {
        let account = Account(id: AccountID(rawValue: "a"), email: "a@example.com", color: .teal, service: service)
        let notice = AccountProblemNotice(account: account, problem: .signInRejected)
        #expect(notice.fixTitle == fix)
        #expect(notice.message.contains("a@example.com"))
    }

    @Test func theAlertOffersEachAccountsFixThenNotNow() {
        let one = AccountProblemNotice(account: gmail, problem: .signInRejected)
        let two = AccountProblemNotice(account: icloud, problem: .signInRejected)
        #expect(UIAlertController.accountProblems([one]) { _ in }.actions.map(\.title) == ["Sign In Again", "Not Now"])
        #expect(
            UIAlertController.accountProblems([one, two]) { _ in }.actions.map(\.title) == [
                "Sign In Again: g@gmail.com", "Update Password: i@icloud.com", "Not Now",
            ])
    }
}

/// A sign-in the mail server turned down, as an IMAP provider's error says it.
private struct IMAPSignInRejected: SignInRejecting {
    var rejectsSignIn: Bool { true }
}
