import Foundation
import MailCore
import MailNotifications
import MailUI

extension SenderPictures {
    /// A sender's photo from Contacts when the reader saved one, else their company's logo from the App Group's
    /// cache, which new-mail alerts fill too, so a logo fetched for an alert shows in the Inbox without asking again.
    static func contactsThenLogos() -> SenderPictures {
        // Unsigned simulator builds have no App Group.
        let directory = (SharedContainer.directoryURL ?? URL.cachesDirectory).appending(path: "SenderPictures")
        let logos = SenderLogos(directory: directory)
        // Decoded for the sharpest screen; pictures are small enough that one size serves every device.
        return SenderPictures(scale: 3) { address in
            if let photo = ContactPhotos.photo(for: address) { return photo }
            return await logos.logo(for: address)
        }
    }
}
