public import MailCore
import UIKit

/// A thread answers, moves, marks, prints and switches its layout from the menu bar and the keyboard, as its toolbar
/// does, and the menu names what each does to it now: Mark as Read or Unread, Star or Unstar, Pin or Unpin.
extension ThreadViewController: CommandScreen {
    public func answer(to command: MailCommand) -> CommandAnswer {
        let model = viewModel
        if let typed = typing.answer(to: command, send: { [composer] in composer.send() }) { return typed }
        if let answer = command.answer { return .ready(perform: { model.answer(answer) }) }
        if let answer = model.senderAnswer(to: command) { return answer }
        let place = ThreadPlace(model.thread, in: model.mailbox)
        switch command {
        // What the place's Archive means, as its swipe does: back to the Inbox from Spam, out of Trash.
        case .archive:
            guard case .perform(let action) = SwipeChoice.archive.swipe(for: model.thread, at: place) else {
                return .unavailable
            }
            return .ready(perform: { model.perform(action) }, title: action.title)
        // In Trash, the toolbar offers Delete Forever, which asks first; the keyboard leaves that to the button.
        case .trash: return model.isInTrash ? .unavailable : .ready(perform: { model.perform(.trash) })
        case .reportSpam:
            guard place.canReportSpam else { return .unavailable }
            return .ready(perform: { model.perform(.reportSpam) })
        case .move: return .ready(perform: { model.move() })
        case .changeLabels: return .ready(perform: { model.changeLabels() })
        case .snooze:
            // Snoozing takes a conversation out of the Inbox for a while; one in Spam or Trash isn't kept that way.
            guard place != .spam, place != .trash else { return .unavailable }
            return .ready(perform: { [weak self] in
                guard let self else { return }
                LaterPickerViewController.presentSnooze(
                    from: self, initial: LaterTime.snoozeChoices(at: .now).first?.date
                ) { model.snooze(until: $0) }
            })
        case .markRead:
            let action = ThreadAction.markRead(model.messages.contains(where: \.isUnread))
            return .ready(perform: { model.perform(action) }, title: action.title)
        case .star:
            let action = ThreadAction.star(!model.isStarred)
            return .ready(perform: { model.perform(action) }, title: action.title)
        case .pin:
            let pin = !model.isPinned
            return .ready(perform: { model.pin(pin) }, title: PinPresentation.title(pin))
        case .mute:
            guard let action = model.muteAction else { return .unavailable }
            return .ready(perform: { model.perform(action) }, title: action.title)
        case .switchLayout:
            return .ready(perform: { model.switchLayout() }, title: model.layout.other.showTitle)
        case .print: return export(to: .print)
        case .exportPDF: return export(to: .share(.pdf))
        case .findInConversation, .findNext, .findPrevious, .zoomIn, .zoomOut, .actualSize, .quickLook:
            return readerAnswer(to: command)
        default: return .notHere
        }
    }

    /// What the keyboard types into in the reader now.
    var typing: ReaderTyping {
        if composer.isTyping { return .reply(sendable: composer.unsent != nil) }
        if findBar.isTyping { return .find }
        return .conversation
    }

    /// The Share menu's export of the conversation, once its messages are in.
    private func export(to destination: ConversationExporter.Destination) -> CommandAnswer {
        guard !viewModel.messages.isEmpty else { return .unavailable }
        return .ready(perform: { [weak self] in
            guard let self else { return }
            exporter.export(exportedConversation, to: destination, anchor: exportAnchor)
        })
    }
}

extension ConversationLayout {
    /// What switching a conversation to this layout says, in the toolbar and the View menu.
    var showTitle: String {
        String(
            localized: "Show as \(title)", table: "Thread", bundle: .module,
            comment: "Switches one conversation's layout; the argument is Classic or Chat")
    }
}
