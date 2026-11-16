import Foundation
import MailCore
import Testing

@testable import MailStore

/// Creating, renaming and deleting user labels through the sync engine: the service changes first, then the store
/// shows the service's labels, and the threads a deleted label held match the service again.
struct LabelEditingTests {
    private let database: MailDatabase
    private let server = FakeMailServer()
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "tester@example.com", color: .teal, service: .gmail)
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LabelEditingTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func engine() -> SyncEngine {
        SyncEngine(accountID: account.id, provider: server, store: database, now: { Self.now })
    }

    private func thread(_ id: String, labels: Set<String>) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "Subject \(id)", snippet: "",
            sender: Contact(name: nil, address: "\(id)@example.com"), date: Self.now.addingTimeInterval(-86_400),
            isUnread: false, messageCount: 1, labelIDs: labels)
    }

    private func storedLabels() throws -> [String: String] {
        Dictionary(uniqueKeysWithValues: try database.labels(for: account.id).map { ($0.id, $0.name) })
    }

    @Test func aCreatedLabelIsStoredAndReturned() async throws {
        let engine = engine()
        try await engine.sync()

        let label = try await engine.createLabel(named: "Projects/Goodmail")

        #expect(label.name == "Projects/Goodmail")
        #expect(label.kind == .user)
        #expect(try storedLabels()[label.id] == "Projects/Goodmail")
    }

    @Test func aNameTheServiceRefusesChangesNothing() async throws {
        let engine = engine()
        try await engine.sync()

        await #expect(throws: ProviderError.rejected) { try await engine.createLabel(named: "Receipts") }
        #expect(try storedLabels() == ["INBOX": "INBOX", "Label_1": "Receipts"])
    }

    @Test func aRenamedLabelKeepsItsIDAndThreads() async throws {
        server.set("t1", thread("t1", labels: ["INBOX", "Label_1"]))
        let engine = engine()
        try await engine.sync()

        try await engine.renameLabel("Label_1", to: "קבלות")

        #expect(try storedLabels()["Label_1"] == "קבלות")
        #expect(try database.threadIDs(labeled: ["Label_1"], account: account.id) == ["t1"])
    }

    @Test func aDeletedLabelLeavesTheStoreAndItsThreadsAreRefetched() async throws {
        server.set("t1", thread("t1", labels: ["INBOX", "Label_1"]))
        server.set("t2", thread("t2", labels: ["INBOX"]))
        let engine = engine()
        try await engine.sync()

        // The service drops the label from t1 without recording a change, as Gmail does.
        try await engine.deleteLabel("Label_1")

        #expect(try storedLabels() == ["INBOX": "INBOX"])
        #expect(try database.threadIDs(labeled: ["Label_1"], account: account.id).isEmpty)
        #expect(try database.threadIDs(labeled: ["INBOX"], account: account.id).sorted() == ["t1", "t2"])
    }

    @Test func deletingALabelRefetchesTheThreadsOfTheLabelsNestedInIt() async throws {
        let engine = engine()
        try await engine.sync()
        let nested = try await engine.createLabel(named: "Receipts/2026")
        server.set("t1", thread("t1", labels: ["INBOX", nested.id]))
        try await engine.sync()

        try await engine.deleteLabel("Label_1")

        #expect(try storedLabels() == ["INBOX": "INBOX"])
        #expect(try database.threadIDs(labeled: [nested.id], account: account.id).isEmpty)
    }

    @Test func deletingAPathThatIsNoLabelDeletesEveryLabelUnderIt() async throws {
        let engine = engine()
        try await engine.sync()
        let unsubscribed = try await engine.createLabel(named: "Extra/Unsubscribed")
        let old = try await engine.createLabel(named: "Extra/Unsubscribed/Old")
        let other = try await engine.createLabel(named: "Extra/Other")
        _ = try await engine.createLabel(named: "Extras")
        server.set("t1", thread("t1", labels: ["INBOX", old.id]))
        server.set("t2", thread("t2", labels: ["INBOX", other.id]))
        try await engine.sync()

        try await engine.deleteLabels(under: "Extra")

        #expect(
            Set(try storedLabels().values) == ["INBOX", "Receipts", "Extras"], "not a name that only starts the same")
        #expect(try storedLabels()[unsubscribed.id] == nil)
        #expect(try database.threadIDs(labeled: [old.id, other.id], account: account.id).isEmpty)
        #expect(try database.threadIDs(labeled: ["INBOX"], account: account.id).sorted() == ["t1", "t2"])
    }

    @Test func renamingAPathThatIsNoLabelMovesEveryLabelUnderIt() async throws {
        let engine = engine()
        try await engine.sync()
        let unsubscribed = try await engine.createLabel(named: "Extra/Unsubscribed")
        let old = try await engine.createLabel(named: "Extra/Unsubscribed/Old")
        let other = try await engine.createLabel(named: "Extra/Other")
        let extras = try await engine.createLabel(named: "Extras")

        try await engine.renameLabels(under: "Extra", to: "נוספים")

        let stored = try storedLabels()
        #expect(stored[unsubscribed.id] == "נוספים/Unsubscribed")
        #expect(stored[old.id] == "נוספים/Unsubscribed/Old")
        #expect(stored[other.id] == "נוספים/Other")
        #expect(stored[extras.id] == "Extras")
    }

    @Test func aGroupRenameRefusedPartwayStoresWhatTheServiceDid() async throws {
        let engine = engine()
        try await engine.sync()
        let first = try await engine.createLabel(named: "Extra/A")
        let second = try await engine.createLabel(named: "Extra/B")
        _ = try await engine.createLabel(named: "Moved/B")

        await #expect(throws: ProviderError.rejected) { try await engine.renameLabels(under: "Extra", to: "Moved") }

        #expect(try storedLabels()[first.id] == "Moved/A", "the service renamed it before refusing the next")
        #expect(try storedLabels()[second.id] == "Extra/B")
    }

    @Test func labelsASyncReadBeforeALabelEditAreDropped() async throws {
        let engine = engine()
        try await engine.sync()
        server.onLabelsRead { [server] in
            server.onLabelsRead(nil)
            _ = try? await engine.createLabel(named: "New")
        }

        try await engine.sync()

        #expect(try storedLabels().values.contains("New"), "the sync's older read doesn't replace the edit's")
    }
}
