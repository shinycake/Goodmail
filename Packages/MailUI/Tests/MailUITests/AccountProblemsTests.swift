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
        navigate: @escaping (Route) -> Void = { _ in }
    ) -> MailboxViewModel {
        MailboxViewModel(
            mailbox: mailbox, accounts: [gmail, icloud], source: .flat { AsyncThrowingStream { $0.finish() } },
            refresh: refresh, navigate: navigate, health: health)
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
        health.forget(gmail.id)
        #expect(health.health.isEmpty)
    }

    @Test func fixingATurnedDownSignInOpensTheSignIn() async {
        var routes: [Route] = []
        let model = viewModel(health: AccountHealthBoard(), navigate: { routes.append($0) })
        await model.fix(AccountProblemNotice(account: gmail, problem: .signInRejected))
        #expect(routes == [.signInAgain(gmail.id)])
    }

    @Test func fixingAFailingSyncSyncsNow() async {
        var refreshed = 0
        let model = viewModel(health: AccountHealthBoard(), refresh: { refreshed += 1 })
        await model.fix(AccountProblemNotice(account: icloud, problem: .cantSync(.timedOut)))
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
