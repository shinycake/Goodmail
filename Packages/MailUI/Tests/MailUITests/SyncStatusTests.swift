import Foundation
import MailCore
import Testing

@testable import MailUI

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The sidebar's footer line on a desktop window: the accounts' problem first, else a check under way, else when mail
/// last came in.
@MainActor struct SyncStatusTests {
    private let gmail = Account(id: AccountID(rawValue: "g"), email: "g@gmail.com", color: .teal, service: .gmail)
    private let icloud = Account(id: AccountID(rawValue: "i"), email: "i@icloud.com", color: .orange, service: .icloud)
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func nothingIsSaidBeforeTheFirstSync() {
        #expect(SyncStatus(AccountHealthBoard(), accounts: [gmail]) == .quiet)
    }

    @Test func aSyncUnderWayIsChecking() {
        let board = AccountHealthBoard()
        board.syncStarted()
        #expect(SyncStatus(board, accounts: [gmail]) == .checking)
        board.syncEnded()
        #expect(SyncStatus(board, accounts: [gmail]) == .quiet)
    }

    @Test func aSyncThatWorkedSaysWhen() {
        var now = start
        let board = AccountHealthBoard(now: { now })
        board.syncStarted()
        board.record(.success(()), for: gmail.id)
        board.syncEnded()
        #expect(SyncStatus(board, accounts: [gmail]) == .updated(start))
        now = start.addingTimeInterval(30)
        board.record(.success(()), for: gmail.id)
        #expect(SyncStatus(board, accounts: [gmail]) == .updated(start.addingTimeInterval(30)), "each sync moves it")
    }

    @Test func aProblemComesBeforeEverythingElse() {
        let board = AccountHealthBoard()
        board.record(.success(()), for: gmail.id)
        board.record(.failure(OAuthSession.Failure.signedOut), for: icloud.id)
        board.syncStarted()
        #expect(
            SyncStatus(board, accounts: [gmail, icloud])
                == .problem(AccountProblemNotice(account: icloud, problem: .signInRejected)))
    }

    @Test func theLineSaysHowLongAgo() {
        #expect(SyncStatus.updated(start).text(now: start.addingTimeInterval(20)) == "Updated just now")
        #expect(SyncStatus.updated(start).text(now: start.addingTimeInterval(5 * 60)) == "Updated 5 minutes ago")
        #expect(SyncStatus.checking.text(now: start) == "Checking for mail…")
        #expect(SyncStatus.quiet.text(now: start) == nil)
        let notice = AccountProblemNotice(account: icloud, problem: .signInRejected)
        #expect(SyncStatus.problem(notice).text(now: start) == "i@icloud.com: Sign-In Needed")
    }
}
