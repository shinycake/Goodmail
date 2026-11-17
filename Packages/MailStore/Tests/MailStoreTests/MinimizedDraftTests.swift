import Foundation
import GRDB
import MailCore
import Testing

@testable import MailStore

/// The messages minimized at the bottom of a window outlast the app, so the bar comes back after a relaunch.
struct MinimizedDraftTests {
    private let database: MailDatabase
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .icloud)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MinimizedDraftTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func draft(_ subject: String) -> Draft {
        Draft(accountID: account.id, subject: subject, body: MessageBody(plain: "About \(subject)"))
    }

    @Test func nothingIsMinimizedAtFirst() throws {
        #expect(try database.claimMinimizedDrafts(for: "w1").isEmpty)
    }

    @Test func aWindowsDraftsComeBackInOrder() throws {
        let drafts = [draft("Lunch"), draft("Budget"), draft("Trip")]
        try database.keepMinimizedDrafts(drafts, for: "w1")
        #expect(try database.claimMinimizedDrafts(for: "w1") == drafts)
    }

    @Test func aDraftThatNoLongerReadsIsSkippedAndTheRestComeBack() throws {
        let lunch = draft("Lunch")
        let budget = draft("Budget")
        try database.keepMinimizedDrafts([lunch, budget], for: "w1")
        try database.write { db in
            try db.execute(
                sql: "UPDATE minimizedDraft SET draft = '{\"not\": \"a draft\"}' WHERE draftID = ?",
                arguments: [lunch.id.uuidString])
        }
        #expect(try database.claimMinimizedDrafts(for: "w2") == [budget])
    }

    @Test func keepingAgainReplacesTheWindowsDrafts() throws {
        let lunch = draft("Lunch")
        var budget = draft("Budget")
        try database.keepMinimizedDrafts([lunch, budget], for: "w1")
        budget.subject = "Q4 budget"
        try database.keepMinimizedDrafts([budget], for: "w1")
        #expect(try database.claimMinimizedDrafts(for: "w1") == [budget])
    }

    @Test func aWindowLeavesTheOthersDraftsAlone() throws {
        let lunch = draft("Lunch")
        let budget = draft("Budget")
        try database.keepMinimizedDrafts([lunch], for: "w1")
        try database.keepMinimizedDrafts([budget], for: "w2")
        try database.keepMinimizedDrafts([], for: "w1")
        #expect(try database.claimMinimizedDrafts(for: "w3") == [budget])
    }

    @Test func aWindowStillOpenKeepsItsDrafts() throws {
        let lunch = draft("Lunch")
        let budget = draft("Budget")
        try database.keepMinimizedDrafts([lunch], for: "open")
        try database.keepMinimizedDrafts([budget], for: "closed")
        #expect(try database.claimMinimizedDrafts(for: "new", sparing: ["open"]) == [budget])
        #expect(try database.claimMinimizedDrafts(for: "open", sparing: ["open", "new"]) == [lunch])
    }

    @Test func theFirstWindowAfterALaunchClaimsEveryDraft() throws {
        let lunch = draft("Lunch")
        let budget = draft("Budget")
        try database.keepMinimizedDrafts([lunch], for: "old window")
        try database.keepMinimizedDrafts([budget], for: "other old window")
        #expect(Set(try database.claimMinimizedDrafts(for: "new").map(\.id)) == [lunch.id, budget.id])
        // A window opened beside it finds nothing to take back.
        #expect(try database.claimMinimizedDrafts(for: "second new", sparing: ["new"]).isEmpty)
        // Claimed drafts belong to the new window, which replaces them as it changes.
        try database.keepMinimizedDrafts([lunch], for: "new")
        #expect(try database.claimMinimizedDrafts(for: "new") == [lunch])
    }

    @Test func aDraftMovedToAnotherWindowLeavesTheFirst() throws {
        let lunch = draft("Lunch")
        try database.keepMinimizedDrafts([lunch], for: "w1")
        try database.keepMinimizedDrafts([lunch], for: "w2")
        #expect(try database.claimMinimizedDrafts(for: "w3") == [lunch])
    }

    @Test func removingTheAccountRemovesItsDrafts() throws {
        try database.keepMinimizedDrafts([draft("Lunch")], for: "w1")
        try database.removeAccount(account.id)
        #expect(try database.claimMinimizedDrafts(for: "w1").isEmpty)
    }
}

/// Writes that arrive out of order never replace a newer version of a window's drafts.
struct MinimizedDraftStoreTests {
    private let database: MailDatabase
    private let store: MinimizedDraftStore
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .icloud)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "MinimizedDraftStoreTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
        store = MinimizedDraftStore(database: database)
    }

    private func draft(_ subject: String) -> Draft {
        Draft(accountID: account.id, subject: subject)
    }

    @Test func aStaleWriteLeavesTheNewerOne() async throws {
        let newer = [draft("Lunch on Friday")]
        #expect(try await store.keep(newer, for: "w1", version: 2))
        #expect(try await !store.keep([draft("Lunch")], for: "w1", version: 1))
        #expect(try await store.claim(for: "w1", sparing: []) == newer)
    }

    @Test func writesInOrderEachLand() async throws {
        try await store.keep([draft("Lunch")], for: "w1", version: 1)
        let latest = [draft("Lunch"), draft("Budget")]
        #expect(try await store.keep(latest, for: "w1", version: 2))
        #expect(try await store.claim(for: "w1", sparing: []) == latest)
    }

    @Test func eachWindowCountsItsOwnVersions() async throws {
        let lunch = [draft("Lunch")]
        let budget = [draft("Budget")]
        try await store.keep(lunch, for: "w1", version: 5)
        #expect(try await store.keep(budget, for: "w2", version: 3))
        #expect(try await store.claim(for: "w2", sparing: ["w1"]) == budget)
    }

    @Test func aFailedWriteLetsTheSameVersionTryAgain() async throws {
        // A draft from an account the database doesn't know breaks the account reference.
        let stranger = Draft(accountID: AccountID(rawValue: "gone"), subject: "Lost")
        await #expect(throws: (any Error).self) { try await store.keep([stranger], for: "w1", version: 1) }
        let lunch = [draft("Lunch")]
        #expect(try await store.keep(lunch, for: "w1", version: 1))
        #expect(try await store.claim(for: "w1", sparing: []) == lunch)
    }
}
