import Foundation
import MailCore
import Synchronization

/// A mail service that answers with the messages it was given, and counts how often it was asked for them.
final class ScriptedProvider: MailProvider {
    private let messages: [String: [Message]]
    private let fetches = Mutex(0)

    init(messages: [String: [Message]]) {
        self.messages = messages
    }

    /// How many times a thread's messages were fetched.
    var fetchCount: Int { fetches.withLock { $0 } }

    func messages(inThread threadID: String) async throws -> [Message] {
        fetches.withLock { $0 += 1 }
        guard let messages = messages[threadID] else { throw ProviderError.notFound }
        return messages
    }

    // The host needs nothing else from a service.
    func labels() async throws -> [MailLabel] { [] }
    func currentCursor() async throws -> String { "0" }
    func threads(matching query: ThreadQuery, pageToken: String?) async throws -> ThreadPage {
        ThreadPage(threads: [], nextPageToken: nil)
    }
    func threads(withIDs ids: [String]) async throws -> ThreadFetch { ThreadFetch(found: [], missing: ids) }
    func changes(since cursor: String) async throws -> ChangeSet { ChangeSet(threadIDs: [], cursor: cursor) }
    func data(for attachment: Attachment, in message: Message.ID) async throws -> Data { Data() }
    func source(of message: Message.ID) async throws -> Data { Data() }
    func perform(_ action: ThreadAction, onThread threadID: String) async throws {}
    var sending: Sending { .direct(NoSending()) }
    func saveDraft(_ raw: Data, inThread threadID: String?, replacing: Message.ID?) async throws -> Message.ID? { nil }
    func deleteDraft(_ message: Message.ID) async throws {}
    func contacts() async throws -> [Contact] { [] }
    func createLabel(named name: String) async throws -> MailLabel { throw ProviderError.rejected }
    func renameLabel(_ id: String, to name: String) async throws {}
    func deleteLabel(_ id: String) async throws {}
}

private struct NoSending: DirectSending {
    func send(_ raw: Data, inThread threadID: String?) async throws {}
}
