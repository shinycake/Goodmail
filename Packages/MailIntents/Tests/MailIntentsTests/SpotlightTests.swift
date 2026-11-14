import Foundation
import MailCore
import Synchronization
import Testing

@testable import MailIntents

struct SpotlightTests {
    private let account = Account(
        id: AccountID(rawValue: "A1"), email: "tester@example.com", color: .teal, service: .gmail)

    private func thread(_ id: String, labels: Set<String>) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "Subject \(id)", snippet: "Snippet",
            sender: Contact(name: "Yael", address: "yael@example.com"), date: .now, isUnread: false,
            messageCount: 1, labelIDs: labels)
    }

    private var host: FakeHost {
        var host = FakeHost(accountList: [account])
        host.stored = [
            thread("inbox", labels: [SystemLabel.inbox]), thread("archived", labels: []),
            thread("spam", labels: [SystemLabel.spam]), thread("trash", labels: [SystemLabel.trash]),
        ]
        return host
    }

    @Test func refreshIndexesLiveConversationsAndTakesOutSpamAndTrash() async throws {
        let index = RecordingIndex()
        try await SpotlightIndexer(host: host, index: index).refresh()
        #expect(index.calls == [.index(["A1/inbox", "A1/archived"]), .remove(["A1/spam", "A1/trash"])])
    }

    @Test func rebuildEmptiesTheIndexFirst() async throws {
        let index = RecordingIndex()
        try await SpotlightIndexer(host: host, index: index).rebuild()
        #expect(index.calls.first == .removeAll)
        #expect(index.calls.count == 3)
    }

    @Test func indexedConversationsCarryNoMessages() throws {
        var host = host
        host.cached[ThreadSummary.ID(accountID: account.id, threadID: "inbox")] = [
            Message(
                id: Message.ID(accountID: account.id, messageID: "m"), threadID: "inbox",
                from: Contact(name: nil, address: "a@example.com"), subject: "Hi", date: .now,
                labelIDs: [SystemLabel.inbox], body: MessageBody(plain: "Body"))
        ]
        let change = try Catalog(host: host).spotlightChange(window: 10)
        #expect(change.index.allSatisfy { $0.messages.isEmpty })
    }

    @Test func spotlightShowsTheSubjectSnippetAndSender() throws {
        let entity = ThreadEntity(thread("inbox", labels: [SystemLabel.inbox]), messages: [])
        #expect(entity.attributeSet.title == "Subject inbox")
        #expect(entity.attributeSet.contentDescription == "Snippet")
        #expect(entity.attributeSet.authorNames == ["Yael"])
    }
}

/// Records the calls made to the index, in order.
final class RecordingIndex: SpotlightIndex {
    enum Call: Equatable {
        case index([String])
        case remove([String])
        case removeAll
    }

    private let recorded = Mutex<[Call]>([])
    var calls: [Call] { recorded.withLock { $0 } }

    func index(_ threads: [ThreadEntity]) async throws { recorded.withLock { $0.append(.index(threads.map(\.id))) } }
    func remove(_ identifiers: [String]) async throws { recorded.withLock { $0.append(.remove(identifiers)) } }
    func removeAll() async throws { recorded.withLock { $0.append(.removeAll) } }
}
