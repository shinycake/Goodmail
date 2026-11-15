import Foundation
import MailCore
import MailNotifications
import MailStore
import MailUI

extension SenderPictures {
    /// Senders' pictures from the App Group's cache, which new-mail alerts fill too, so a picture fetched for an alert
    /// shows in the Inbox without asking again.
    static func cached(with database: MailDatabase) -> SenderPictures {
        // Unsigned simulator builds have no App Group.
        let directory = (SharedContainer.directoryURL ?? URL.cachesDirectory).appending(path: "SenderPictures")
        let sources = SenderPictureSources(directory: directory, database: database)
        // Decoded for the sharpest screen; pictures are small enough that one size serves every device.
        return SenderPictures(scale: 3) { await sources.picture(for: $0) }
    }
}
