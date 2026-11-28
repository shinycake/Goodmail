import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// The accounts and signatures the app reads at once follow every write to them, in order, each as new as the
/// revision its write returned.
@Suite(.timeLimit(.minutes(2)))
struct StoredAccountsTests {
    private let url = FileManager.default.temporaryDirectory
        .appending(path: "StoredAccountsTests-\(UUID().uuidString)")
        .appending(path: "mail.sqlite")
    private let home = Account(
        id: AccountID(rawValue: "home"), email: "home@example.com", color: .teal, service: .gmail)
    private let work = Account(
        id: AccountID(rawValue: "work"), email: "work@example.com", color: .orange, service: .gmail)

    @Test func theStreamFollowsEachAccountAndSignatureWriteAtItsRevision() async throws {
        let database = try await OffMainDatabase.open(url: url)
        let (home, work) = (home, work)
        var followed = database.accountsAndSignatures().makeAsyncIterator()
        func next() async throws -> StoredAccounts? { try await followed.next(isolation: #isolation) }

        #expect(try await next() == StoredAccounts(accounts: [], signatures: [:], revision: 0))
        var revision = try await database.offMain { try $0.save(home) }
        #expect(try await next() == StoredAccounts(accounts: [home], signatures: [:], revision: revision))
        revision = try await database.offMain { try $0.save(work) }
        #expect(try await next() == StoredAccounts(accounts: [home, work], signatures: [:], revision: revision))
        try await database.offMain { try $0.apply(StoreChanges(accountID: work.id, signature: "Dana at work")) }
        let signed = try await database.offMain { try $0.accountsRevision() }
        #expect(signed > revision)
        #expect(
            try await next()
                == StoredAccounts(accounts: [home, work], signatures: [work.id: "Dana at work"], revision: signed))
        revision = try await database.offMain { try $0.reorderAccounts([work.id]) }
        let reordered = try await next()
        #expect(reordered?.accounts == [work, home])
        #expect(reordered?.revision == revision)
        var named = home
        named.name = "Dana"
        let renamed = named
        revision = try await database.offMain { try $0.update(renamed) }
        let afterRename = try await next()
        #expect(afterRename?.accounts == [work, renamed])
        #expect(afterRename?.revision == revision)
        revision = try await database.offMain { try $0.removeAccount(work.id) }
        #expect(try await next() == StoredAccounts(accounts: [renamed], signatures: [:], revision: revision))
        #expect(
            try await database.offMain { try $0.storedAccounts() }
                == StoredAccounts(accounts: [renamed], signatures: [:], revision: revision))
    }

    @Test func eachChangeToTheAccountsRevisesThemAndOneThatChangesNothingDoesnt() async throws {
        let database = try await OffMainDatabase.open(url: url)
        let home = home
        var work = work
        work.aliases = [
            Contact(name: "Dana", address: "dana@example.com"), Contact(name: nil, address: "d@example.com"),
        ]
        let aliased = work
        let revisions = try await database.offMain { database in
            let added = [try database.save(home), try database.save(aliased)]
            let reordered = try database.reorderAccounts([aliased.id])
            try database.apply(StoreChanges(accountID: aliased.id, aliases: aliased.aliases))
            let sameAliases = try database.accountsRevision()
            let sameName = try database.update(home)
            let signed = try database.storeSignature("Dana", for: home.id)
            let sameSignature = try database.storeSignature("Dana", for: home.id)
            let recolored = try database.update(Account(id: home.id, email: home.email, color: .blue, service: .gmail))
            return added + [reordered, sameAliases, sameName, signed, sameSignature, recolored]
        }
        let (changed, unchanged) = ([0, 1, 2, 5, 7], [3, 4, 6])
        #expect(zip(changed, changed.dropFirst()).allSatisfy { revisions[$0] < revisions[$1] }, "\(revisions)")
        #expect(
            unchanged.allSatisfy { revisions[$0] == revisions[$0 - 1] },
            "the same aliases, name and signature again: \(revisions)")
    }

    /// The columns of `account` a change to which doesn't change what `StoredAccounts` reads, so it needn't bump the
    /// revision. Every other column must.
    static let columnsTheRevisionLeavesOut: Set<String> = [
        // Which accounts the Focus shows, read by the mail lists, not by the accounts.
        "inFocus"
    ]

    @Test func everyAccountColumnButThoseLeftOutRevisesTheAccounts() async throws {
        let database = try await OffMainDatabase.open(url: url)
        let (columns, trigger) = try await database.offMain { database in
            try database.read { db in
                (
                    try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('account')"),
                    try String.fetchOne(
                        db, sql: "SELECT sql FROM sqlite_master WHERE name = 'account_revisedByUpdate'") ?? ""
                )
            }
        }
        let watched = Set(
            trigger.matches(of: /OLD\.(\w+) IS NOT NEW\.(\w+)/).compactMap { $0.1 == $0.2 ? String($0.1) : nil })
        #expect(watched == Set(columns).subtracting(Self.columnsTheRevisionLeavesOut))
    }

    @Test func theRevisionLivesInTheFileSoAWriteThroughAnotherConnectionBumpsIt() async throws {
        let home = home
        let here = try await OffMainDatabase.open(url: url)
        let other = try await OffMainDatabase.open(url: url)
        let before = try await here.offMain { try $0.accountsRevision() }
        _ = try await other.offMain { try $0.save(home) }
        #expect(try await here.offMain { try $0.accountsRevision() } > before)
    }
}
