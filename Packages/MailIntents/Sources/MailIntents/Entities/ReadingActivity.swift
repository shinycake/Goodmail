import AppIntents
public import Foundation
public import MailCore

extension NSUserActivity {
    /// The conversation on screen, as Siri and Apple Intelligence see it, so "summarize this email" or "reply to
    /// this" acts on it. Set on the reader, it is current while the reader shows.
    public static func reading(_ thread: ThreadSummary) -> NSUserActivity {
        let activity = NSUserActivity(activityType: "com.idanbirman.goodmail.reading")
        activity.title = thread.subject
        // Spotlight already holds the conversation as an indexed entity.
        activity.isEligibleForSearch = false
        activity.appEntityIdentifier = EntityIdentifier(for: ThreadEntity.self, identifier: EntityID.string(thread.id))
        return activity
    }
}
