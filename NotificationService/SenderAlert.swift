import MailCore
import MailNotifications
import UIKit
import UserNotifications

/// A new-mail alert with the sender's picture: their photo, their company's logo, or else their initials.
enum SenderAlert {
    static func content(for mail: NewMail, in account: Account, pictures: SenderPictureSources?) async
        -> UNNotificationContent
    {
        let sender = mail.thread.sender
        var picture = await pictures?.picture(for: sender.address)
        if picture == nil { picture = monogram(for: sender.displayName) }
        return await CommunicationAlert.content(for: mail, in: account, picture: picture)
    }

    /// The sender's initials on a neutral circle, readable on light and dark alerts. `nil` for a name with no
    /// letters, which iOS shows as a person.
    static func monogram(for name: String) -> Data? {
        let initials = Monogram.initials(for: name)
        guard !initials.isEmpty else { return nil }
        let side: CGFloat = 120
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).pngData { context in
            UIColor.systemGray.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).setFill()
            context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            let font = UIFont.systemFont(ofSize: 48, weight: .semibold)
            let text = NSAttributedString(
                string: initials,
                attributes: [
                    .font: font.fontDescriptor.withDesign(.rounded).map { UIFont(descriptor: $0, size: 48) } ?? font,
                    .foregroundColor: UIColor.white,
                ])
            let size = text.size()
            text.draw(at: CGPoint(x: (side - size.width) / 2, y: (side - size.height) / 2))
        }
    }
}
