import Foundation
import MailCore
import Testing

@testable import OutlookProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// The newest change in the mailbox is m3's, at 09:30 on 10 November. Since then m4 (conversation c2) changed, m5
/// (c5) went to Deleted Items, and m9 (c7) was deleted from there for good.
struct OutlookSyncTests {
    private static let watermark = Date(timeIntervalSince1970: 1_794_303_000)  // 2026-11-10T09:30:00Z
    private static let trashDelta = "https://graph.microsoft.com/v1.0/me/mailFolders/AATrash/messages/delta"

    private static func mailbox(_ request: URLRequest) -> String? {
        switch (request.graphPath, request.query("$orderby")) {
        case ("me/messages", "lastModifiedDateTime desc"): return "latest-modified"
        case ("me/messages", "lastModifiedDateTime"): return "modified-since"
        case ("me/mailFolders/AATrash/messages/delta", _):
            switch (request.query("$skiptoken"), request.query("$deltatoken")) {
            case (nil, nil): return "trash-delta-start"
            case ("s1", nil): return "trash-delta-s1"
            case (nil, "d1"): return "trash-delta-d1"
            default: return "status-410"
            }
        default: return FixtureGraph.mailbox(request)
        }
    }

    @Test func theCursorIsTheNewestChangeAndWhereDeletedItemsLeftOff() async throws {
        let outlook = try await OutlookClient.signedIn(to: FixtureGraph(Self.mailbox))
        let cursor = try OutlookCursor(try await outlook.currentCursor())
        #expect(cursor.modifiedSince == Self.watermark)
        #expect(cursor.deletedItems == URL(string: Self.trashDelta + "?$deltatoken=d1"))
    }

    @Test func changesNameModifiedConversationsAndOnesDeletedForGood() async throws {
        let index = MemoryIndex([MessageIndexEntry(key: "m9", threadID: "c7")])
        let graph = FixtureGraph(Self.mailbox)
        let outlook = try await OutlookClient.signedIn(to: graph, index: index)
        let cursor = OutlookCursor(
            modifiedSince: Self.watermark, deletedItems: URL(string: Self.trashDelta + "?$deltatoken=d1"))
        let changes = try await outlook.changes(since: cursor.rawValue)

        // m3 changed at the cursor itself, so its conversation was already read.
        #expect(changes.threadIDs == ["c2", "c5", "c7"])
        let next = try OutlookCursor(changes.cursor)
        #expect(next.modifiedSince > Self.watermark)
        #expect(next.deletedItems == URL(string: Self.trashDelta + "?$deltatoken=d2"))
        #expect(index.all == [MessageIndexEntry(key: "m4", threadID: "c2")])

        let query = try #require(graph.requests.first { $0.query("$orderby") == "lastModifiedDateTime" })
        #expect(query.query("$filter") == "lastModifiedDateTime ge 2026-11-10T09:30:00Z")
    }

    @Test func aForgottenDeltaOrAForeignCursorMeansAFullSync() async throws {
        let outlook = try await OutlookClient.signedIn(to: FixtureGraph(Self.mailbox))
        let stale = OutlookCursor(
            modifiedSince: Self.watermark, deletedItems: URL(string: Self.trashDelta + "?$deltatoken=old"))
        await #expect(throws: ProviderError.cursorExpired) { try await outlook.changes(since: stale.rawValue) }
        await #expect(throws: ProviderError.cursorExpired) { try await outlook.changes(since: "12345") }
    }

    @Test func fetchedConversationsGoIntoTheIndex() async throws {
        let index = MemoryIndex()
        let outlook = try await OutlookClient.signedIn(to: FixtureGraph(Self.mailbox), index: index)
        _ = try await outlook.threads(withIDs: ["c1", "c2"])
        #expect(
            index.all == [
                MessageIndexEntry(key: "m1", threadID: "c1"), MessageIndexEntry(key: "m3", threadID: "c1"),
                MessageIndexEntry(key: "m4", threadID: "c2"),
            ])
    }
}
