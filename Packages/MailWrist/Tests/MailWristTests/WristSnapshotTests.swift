import Foundation
import MailCore
import Testing

@testable import MailWrist

/// The Inbox the iPhone sends the watch: pinned first, capped, small, and readable by the next version.
struct WristSnapshotTests {
    private let work = Account(
        id: AccountID(rawValue: "work"), email: "me@work.example", color: .orange, service: .gmail)
    private let home = Account(
        id: AccountID(rawValue: "home"), email: "me@home.example", color: .blue, service: .icloud)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func thread(_ id: String, minutesAgo: Double, subject: String = "Lunch", snippet: String = "")
        -> ThreadSummary
    {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: work.id, threadID: id), subject: subject, snippet: snippet,
            sender: Contact(name: "Maya", address: "maya@example.com"), date: now.addingTimeInterval(-minutesAgo * 60),
            isUnread: true, messageCount: 2, labelIDs: ["INBOX"])
    }

    @Test func pinnedRowsComeFirstThenTheRestNewestFirst() {
        let pinned = thread("pinned", minutesAgo: 90)
        let snapshot = WristSnapshot(
            accounts: [work], threads: [thread("mid", minutesAgo: 30), pinned, thread("new", minutesAgo: 1)],
            pinned: [pinned.id], unread: [:], madeAt: now)
        #expect(snapshot.rows.map(\.id.threadID) == ["pinned", "new", "mid"])
        #expect(snapshot.rows.map(\.isPinned) == [true, false, false])
    }

    @Test func keepsAtMostTheRowLimit() {
        let threads = (0..<40).map { thread("t\($0)", minutesAgo: Double($0)) }
        let snapshot = WristSnapshot(accounts: [work], threads: threads, pinned: [], unread: [:], madeAt: now)
        #expect(snapshot.rows.count == WristSnapshot.rowLimit)
        #expect(snapshot.rows.last?.id.threadID == "t24")
    }

    @Test func accountsCarryTheirAddressColorUnreadCountAndService() {
        let snapshot = WristSnapshot(
            accounts: [work, home], threads: [], pinned: [], unread: [work.id: 3], madeAt: now)
        #expect(
            snapshot.accounts == [
                WristAccount(id: work.id, address: "me@work.example", color: .orange, unread: 3, service: .gmail),
                WristAccount(id: home.id, address: "me@home.example", color: .blue, unread: 0, service: .icloud),
            ])
        #expect(snapshot.unread == 3)
    }

    @Test func cutsLongSnippetsAndFindsCodes() throws {
        let snapshot = WristSnapshot(
            accounts: [work],
            threads: [
                thread(
                    "code", minutesAgo: 1, subject: "Sign in",
                    snippet: "Your verification code is 482913. " + String(repeating: "More words. ", count: 30))
            ],
            pinned: [], unread: [:], madeAt: now)
        let row = try #require(snapshot.rows.first)
        #expect(row.snippet.count == WristSnapshot.snippetLimit)
        #expect(row.code == "482913")
    }

    /// A snippet a provider made from a plain part that is really HTML reaches the watch as its words.
    @Test func aSnippetOfMarkupReachesTheWatchAsWords() throws {
        let snapshot = WristSnapshot(
            accounts: [work],
            threads: [
                thread("html", minutesAgo: 1, subject: "Lunch", snippet: "<div><b>Lunch?</b></div><div>Dana</div>")
            ],
            pinned: [], unread: [:], madeAt: now)
        #expect(try #require(snapshot.rows.first).snippet == "Lunch? Dana")
    }

    @Test func aFullInboxStaysSmall() throws {
        let snippet = String(repeating: "x", count: 200)
        let threads = (0..<WristSnapshot.rowLimit).map { thread("t\($0)", minutesAgo: Double($0), snippet: snippet) }
        let snapshot = WristSnapshot(accounts: [work, home], threads: threads, pinned: [], unread: [:], madeAt: now)
        #expect(try snapshot.encoded().count < 16_000)
    }

    @Test func readsBackWhatItSent() throws {
        let snapshot = WristSnapshot(
            accounts: [work], threads: [thread("t1", minutesAgo: 1)], pinned: [], unread: [work.id: 1], madeAt: now)
        #expect(try WristSnapshot.read(snapshot.encoded()) == .snapshot(snapshot))
    }

    @Test func aNewerVersionAsksForAnUpdate() throws {
        let newer = Data(#"{"version": 2, "somethingNew": true}"#.utf8)
        #expect(try WristSnapshot.read(newer) == .newerVersion)
    }

    @Test func aSnapshotFromBeforeAppliedReadsAsApplyingNothing() throws {
        let snapshot = WristSnapshot(accounts: [work], threads: [], pinned: [], unread: [:], madeAt: now)
        var json = try #require(try JSONSerialization.jsonObject(with: snapshot.encoded()) as? [String: Any])
        json["applied"] = nil
        let old = try JSONSerialization.data(withJSONObject: json)
        #expect(try WristSnapshot.read(old) == .snapshot(snapshot))
    }
}
