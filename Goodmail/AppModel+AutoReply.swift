import MailCore
import MailUI

extension AppModel {
    /// The automatic reply of an account whose service sends one, as Settings edits it; `nil` for iCloud, whose
    /// service has no API for it, and for Outlook until it asks for the mailbox settings scope.
    func autoReplyService(for id: AccountID) -> AutoReplyEditor.Service? {
        guard let replying = (try? providers.provider(for: id)) as? any AutoReplying else { return nil }
        return AutoReplyEditor.Service(
            hasSubject: replying.autoReplyHasSubject,
            load: { try await replying.autoReply() },
            save: { try await replying.setAutoReply($0) })
    }
}
