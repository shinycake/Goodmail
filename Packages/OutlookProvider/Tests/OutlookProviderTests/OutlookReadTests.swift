import Foundation
import MailCore
import Testing

@testable import OutlookProvider

struct OutlookReadTests {
    /// A mailbox with every well-known folder but Conversation History, a user folder at the root and one in the
    /// Inbox, and two conversations in the Inbox.
    private static func mailbox(_ request: URLRequest) -> String? {
        let path = request.graphPath
        if request.url!.host() == "login.example.com" { return "token" }
        if let name = path.split(separator: "/").last, path.hasPrefix("me/mailFolders/"),
            WellKnownFolder(rawValue: String(name)) != nil
        {
            return "folder-\(name)"
        }
        switch path {
        case "me/mailFolders": return "folders-root"
        case "me/mailFolders/AAInbox/childFolders": return "folders-inbox-children"
        case "me/mailFolders/AAInbox/messages":
            return request.query("$skip") == nil ? "inbox-page1" : "empty-page"
        case "me/mailFolders/AAProjects/childFolders": return "empty-page"
        case "me/messages":
            switch request.query("$filter") {
            case "conversationId eq 'c1'": return "conversation-c1"
            case "conversationId eq 'c2'": return "conversation-c2"
            default: return "empty-page"
            }
        default: return nil
        }
    }

    @Test func foldersBecomeSystemLabelsAndTheUsersOwnByPath() async throws {
        let outlook = try await OutlookClient.signedIn(to: FixtureGraph(Self.mailbox))
        let labels = try await outlook.labels()

        #expect(
            labels.filter { $0.kind == .system }.map(\.id) == [
                "INBOX", "SENT", "DRAFT", "TRASH", "SPAM", "UNREAD", "STARRED",
            ])
        #expect(
            labels.filter { $0.kind == .user } == [
                MailLabel(id: "AAProjects", name: "Inbox/Projects", kind: .user),
                MailLabel(id: "AAReceipts", name: "קבלות", kind: .user),
            ])
    }

    @Test func aPageListsEachConversationOnceNewestFirst() async throws {
        let graph = FixtureGraph(Self.mailbox)
        let outlook = try await OutlookClient.signedIn(to: graph)
        let page = try await outlook.threads(matching: ThreadQuery(label: SystemLabel.inbox), pageToken: nil)

        #expect(page.threads.map(\.id.threadID) == ["c1", "c2"])
        #expect(page.nextPageToken == "https://graph.microsoft.com/v1.0/me/mailFolders/AAInbox/messages?$skip=3")
        let list = try #require(graph.requests.first { $0.graphPath == "me/mailFolders/AAInbox/messages" })
        #expect(list.query("$orderby") == "receivedDateTime desc")
        #expect(list.query("$filter") == "receivedDateTime ge 1970-01-01T00:00:00Z")
        #expect(list.value(forHTTPHeaderField: "Authorization") == "Bearer eyJ0.fixture-access-token")
        #expect(list.value(forHTTPHeaderField: "Prefer") == #"IdType="ImmutableId""#)

        let next = try await outlook.threads(
            matching: ThreadQuery(label: SystemLabel.inbox), pageToken: page.nextPageToken)
        #expect(next.threads.isEmpty && next.nextPageToken == nil)
    }

    @Test func aConversationSummarizesAllItsMessagesWhateverTheirFolder() async throws {
        let outlook = try await OutlookClient.signedIn(to: FixtureGraph(Self.mailbox))
        let fetch = try await outlook.threads(withIDs: ["c1", "c2", "gone"])

        #expect(fetch.missing == ["gone"])
        let lunch = fetch.found[0]
        #expect(lunch.subject == "Lunch plans")
        #expect(lunch.snippet == "Thursday works")
        #expect(lunch.sender == Contact(name: "Dana Levi", address: "dana@example.com"))
        #expect(lunch.messageCount == 2)
        #expect(lunch.isUnread)
        #expect(lunch.labelIDs == ["INBOX", "SENT", "UNREAD", "STARRED"])
        #expect(fetch.found[1].labelIDs == ["AAProjects"])
    }

    @Test func starredIsAFlagFilterAndACategoryHasNoOutlookMail() async throws {
        let graph = FixtureGraph(Self.mailbox)
        let outlook = try await OutlookClient.signedIn(to: graph)
        let since = Date(timeIntervalSince1970: 1_800_000_000)
        _ = try await outlook.threads(matching: ThreadQuery(label: SystemLabel.starred, since: since), pageToken: nil)
        let list = try #require(graph.requests.last { $0.graphPath == "me/messages" && $0.query("$orderby") != nil })
        #expect(list.query("$filter") == "receivedDateTime ge 2027-01-15T08:00:00Z and flag/flagStatus eq 'flagged'")

        let social = try await outlook.threads(matching: ThreadQuery(label: "CATEGORY_SOCIAL"), pageToken: nil)
        #expect(social.threads.isEmpty && social.nextPageToken == nil)
    }

    @Test func aSearchTakesNoFilterOrOrder() async throws {
        let graph = FixtureGraph(Self.mailbox)
        let outlook = try await OutlookClient.signedIn(to: graph)
        _ = try await outlook.threads(matching: ThreadQuery(text: #"from:dana "lunch""#), pageToken: nil)
        let search = try #require(graph.requests.last { $0.query("$search") != nil })
        #expect(search.query("$search") == #""from:dana lunch""#)
        #expect(search.query("$filter") == nil && search.query("$orderby") == nil)
    }

    @Test func quotesInAConversationIDAreDoubled() {
        #expect(OutlookClient.literal("AAQk'x=") == "'AAQk''x='")
    }
}
