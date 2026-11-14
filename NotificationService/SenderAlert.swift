import Intents
import MailCore
import MailNotifications
import OSLog
import UIKit
import UserNotifications

/// A new-mail alert as a communication alert: iOS shows the sender's picture, with Goodmail's icon as its badge.
enum SenderAlert {
    /// The alert for `thread`, or the plain one when iOS refuses the sender's details.
    static func content(for thread: ThreadSummary, in account: Account, logos: SenderLogos?) async
        -> UNNotificationContent
    {
        let plain = NewMailAlert.content(for: thread, in: account)
        let address = thread.sender.address
        var picture = await logos?.logo(for: address)
        if picture == nil { picture = monogram(for: thread.sender.displayName) }
        let sender = INPerson(
            personHandle: INPersonHandle(value: address, type: .emailAddress), nameComponents: nil,
            displayName: thread.sender.displayName, image: picture.map { INImage(imageData: $0) },
            contactIdentifier: nil, customIdentifier: address)
        let intent = INSendMessageIntent(
            recipients: nil, outgoingMessageType: .outgoingMessageText, content: plain.body, speakableGroupName: nil,
            conversationIdentifier: plain.targetContentIdentifier, serviceName: nil, sender: sender, attachments: nil)
        let interaction = INInteraction(intent: intent, response: nil)
        interaction.direction = .incoming
        do {
            try await interaction.donate()
            guard let alert = try plain.updating(from: intent).mutableCopy() as? UNMutableNotificationContent else {
                return plain
            }
            // Still stacked by account, as plain alerts are, rather than by conversation.
            alert.threadIdentifier = plain.threadIdentifier
            return alert
        } catch {
            Logger.senderAlert.error("Couldn't show the sender: \(error, privacy: .public)")
            return plain
        }
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

extension Logger {
    fileprivate static let senderAlert = Logger(subsystem: "com.idanbirman.goodmail", category: "push")
}
