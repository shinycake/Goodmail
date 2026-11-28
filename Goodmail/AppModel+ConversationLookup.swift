import MailCore
import MailStore

extension AppModel {
    /// Finds a conversation a window was asked to open from outside, as a tapped alert, off the main actor: on the
    /// device, or else from its service, whose answer is stored so the reader's messages have their row (R10).
    var conversationLookup: ConversationLookup {
        #if DEBUG
            // The synthetic mailboxes have no service to ask, so a conversation not in them is one it says is missing.
            let synthetic = SyntheticMailbox.requestedCount != nil
        #else
            let synthetic = false
        #endif
        let store = database.blocking  // blocking-reads: allow: read and written only in `find`, which is @concurrent
        return ConversationLookup(
            stored: { [store] in try store.thread($0) },
            fetch: { [providers] thread in
                if synthetic { return ThreadFetch(found: [], missing: [thread.threadID]) }
                let provider: any MailProvider
                do {
                    provider = try providers.provider(for: thread.accountID)
                } catch Providers.Failure.unknownAccount {
                    return nil
                }
                return try await provider.threads(withIDs: [thread.threadID])
            },
            store: { [store] in try store.apply($0) })
    }
}
