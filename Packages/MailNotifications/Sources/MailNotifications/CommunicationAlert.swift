import Intents
import MailCore
import OSLog
import UserNotifications

/// A new-mail alert as a communication alert, as Gmail's are: the sender's picture with Goodmail's icon as its badge,
/// the sender's name, and the subject in bold above the preview.
public enum CommunicationAlert {
    /// The alert for `mail` showing `picture`, or the plain alert when iOS refuses the sender's details.
    public static func content(for mail: NewMail, in account: Account, picture: Data?) async -> UNNotificationContent {
        let plain = NewMailAlert.content(for: mail, in: account)
        let address = mail.thread.sender.address
        let image = picture.map { INImage(imageData: $0) }
        let sender = INPerson(
            personHandle: INPersonHandle(value: address, type: .emailAddress), nameComponents: nil,
            displayName: mail.thread.sender.displayName, image: image, contactIdentifier: nil,
            customIdentifier: address)
        let me = INPerson(
            personHandle: INPersonHandle(value: account.email, type: .emailAddress), nameComponents: nil,
            displayName: nil, image: nil, contactIdentifier: nil, customIdentifier: nil, isMe: true)
        // iOS drops a communication alert's own subtitle and shows a conversation's name in its place, so the
        // subject is the conversation's name. A name needs more than one recipient, which the reader and the
        // sender are.
        let intent = INSendMessageIntent(
            recipients: [me, sender], outgoingMessageType: .outgoingMessageText, content: plain.body,
            speakableGroupName: INSpeakableString(spokenPhrase: plain.subtitle),
            conversationIdentifier: plain.targetContentIdentifier, serviceName: nil, sender: sender,
            attachments: nil)
        // A named conversation shows its own picture, which is the sender's.
        if let image { intent.setImage(image, forParameterNamed: \.speakableGroupName) }
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
            Logger.communicationAlert.error("Couldn't show the sender: \(error, privacy: .public)")
            return plain
        }
    }
}

extension Logger {
    fileprivate static let communicationAlert = Logger(subsystem: "com.idanbirman.goodmail", category: "push")
}
