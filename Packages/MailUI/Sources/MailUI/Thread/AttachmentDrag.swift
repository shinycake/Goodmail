import MailCore
import UIKit
import UniformTypeIdentifiers

/// Lets an attachment's capsule be dragged out to Finder, the desktop or another app, in a desktop window. Touch
/// keeps the capsule a button. The file is fetched only when the drop asks for it, off the main actor.
final class AttachmentDrag: NSObject, UIDragInteractionDelegate {
    private let attachment: Attachment
    private let message: Message.ID
    private let data: (Attachment, Message.ID) async throws -> Data

    init(
        attachment: Attachment, in message: Message.ID,
        data: @escaping (Attachment, Message.ID) async throws -> Data
    ) {
        self.attachment = attachment
        self.message = message
        self.data = data
    }

    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession)
        -> [UIDragItem]
    {
        guard interaction.view?.traitCollection.interactionStyle == .desktop else { return [] }
        let type =
            UTType(mimeType: attachment.mimeType) ?? UTType(
                filenameExtension: (attachment.filename as NSString).pathExtension) ?? .data
        let provider = NSItemProvider()
        provider.suggestedName = attachment.filename
        provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { [self] deliver in
            // The drop asks on a queue of its own; the fetch is the window's own (`attachmentData`), which keeps the
            // file and does its network and disk work off the main actor.
            let work = Task { @MainActor in
                do {
                    deliver(try await data(attachment, message), nil)
                } catch {
                    deliver(nil, error)
                }
            }
            let progress = Progress(totalUnitCount: 1)
            progress.cancellationHandler = { work.cancel() }
            return progress
        }
        return [UIDragItem(itemProvider: provider)]
    }
}
