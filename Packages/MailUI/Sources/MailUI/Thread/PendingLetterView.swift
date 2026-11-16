import MailCore
import UIKit

/// My reply on its way, in the classic layout: its card, as the message will read once its copy syncs, with the
/// chat's caption under it once it is overdue, scheduled or failed.
final class PendingLetterView: UIView {
    let card: MessageCardView
    private let delivery = ChatDeliveryView()
    private var shownDelivery: ChatTranscript.Delivery?

    init(attachmentData: @escaping (Attachment, Message.ID) async throws -> Data) {
        card = MessageCardView(attachmentData: attachmentData)
        super.init(frame: .zero)
        let stack = UIStackView(arrangedSubviews: [card, delivery])
        stack.axis = .vertical
        stack.spacing = 2
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        delivery.contentHorizontalAlignment = .trailing
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func configure(
        _ reply: PendingReply, dateText: String, accountEmail: String, accountColor: UIColor,
        actions: ChatDeliveryView.Actions
    ) {
        card.configure(
            reply.letter, dateText: dateText, accountEmail: accountEmail, accountColor: accountColor,
            allowsRemoteContent: true)
        delivery.configure(reply.delivery, reply: reply.id, actions: actions)
        delivery.isHidden = reply.delivery.caption == nil
        // The card rises into place the first time, as a chat reply does, and fades while it is overdue.
        ChatDeliveryView.show(reply.delivery, on: card, arriving: shownDelivery == nil)
        shownDelivery = reply.delivery
    }
}
