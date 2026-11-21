import MailCore
import MailStore

extension AppModel {
    /// Finds a conversation a window was asked to open from outside, as a tapped alert, off the main actor: on the
    /// device, or else from its service, whose answer is stored so the reader's messages have their row (R10).
    var conversationLookup: ConversationLookup {
        ConversationLookup(
            stored: { [database] in try database.thread($0) },
            fetch: { [providers] thread in
                let provider: any MailProvider
                do {
                    provider = try providers.provider(for: thread.accountID)
                } catch Providers.Failure.unknownAccount {
                    return nil
                }
                return try await provider.threads(withIDs: [thread.threadID])
            },
            store: { [database] in try database.apply($0) })
    }
}
