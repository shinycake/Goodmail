import Foundation
import MailCore
import MailNotifications
import MailUI

extension SenderPictures {
    /// Company logos from the App Group's cache, which new-mail alerts fill too, so a logo fetched for an alert shows
    /// in the Inbox without asking again.
    static func logos() -> SenderPictures {
        // Unsigned simulator builds have no App Group.
        let directory = (SharedContainer.directoryURL ?? URL.cachesDirectory).appending(path: "SenderPictures")
        let logos = SenderLogos(directory: directory)
        // Decoded for the sharpest screen; pictures are small enough that one size serves every device.
        return SenderPictures(scale: 3) { address in await logos.logo(for: address) }
    }
}
