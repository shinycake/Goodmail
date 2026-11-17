import MailCore
import UIKit

extension ChatTranscript.Delivery {
    /// What the caption under a reply on its way says, and VoiceOver with it. A reply that went needs none: its
    /// bubble in full color says so.
    var caption: String? {
        switch self {
        case .sending:
            String(
                localized: "Sending…", table: "ChatDelivery", bundle: .module,
                comment: "Under a chat reply on its way")
        case .scheduled(let date):
            String(
                localized: "Scheduled for \(ScheduledTime.text(for: date))", table: "ChatDelivery", bundle: .module,
                comment: "Under a chat reply waiting to go; the argument is when")
        case .failed:
            String(
                localized: "Not Delivered", table: "ChatDelivery", bundle: .module,
                comment: "Under a chat reply that failed to send")
        case .sent:
            nil
        }
    }

    /// A reply that hasn't gone yet reads faded, until it goes.
    fileprivate var alpha: CGFloat {
        switch self {
        case .sending, .scheduled: 0.55
        case .failed, .sent: 1
        }
    }
}

/// The caption under my reply while it is on its way: a spinner and "Sending…", a clock and when it is scheduled
/// for, or a red "Not Delivered". Scheduled and failed ones open a menu of what to do with the reply.
final class ChatDeliveryView: UIButton {
    /// What the caption's menu does with a reply.
    struct Actions {
        var retry: (Draft.ID) -> Void
        var edit: (Draft.ID) -> Void
        var discard: (Draft.ID) -> Void
        var moveToDrafts: (Draft.ID) -> Void
    }

    init() {
        var configuration = UIButton.Configuration.plain()
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 4, bottom: 4, trailing: 4)
        configuration.imagePadding = 4
        configuration.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(textStyle: .caption1)
        configuration.activityIndicatorColorTransformer = UIConfigurationColorTransformer { _ in .secondaryLabel }
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .caption1)
            return attributes
        }
        super.init(frame: .zero)
        self.configuration = configuration
        showsMenuAsPrimaryAction = true
        accessibilityIdentifier = "chat.delivery"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func configure(_ delivery: ChatTranscript.Delivery, reply: Draft.ID, actions: Actions) {
        configuration?.title = delivery.caption
        configuration?.showsActivityIndicator = delivery == .sending
        switch delivery {
        case .sending, .sent:
            configuration?.image = nil
            configuration?.baseForegroundColor = .secondaryLabel
            menu = nil
        case .scheduled:
            configuration?.image = UIImage(systemName: "clock")
            configuration?.baseForegroundColor = .secondaryLabel
            menu = UIMenu(children: [
                Self.edit(reply, actions),
                UIAction(
                    title: String(
                        localized: "Move to Drafts", table: "ChatDelivery", bundle: .module,
                        comment: "Keeps a scheduled chat reply in Drafts instead of sending it"),
                    image: UIImage(systemName: "doc")
                ) { _ in actions.moveToDrafts(reply) },
            ])
        case .failed(let failure):
            configuration?.image = UIImage(systemName: "exclamationmark.circle.fill")
            configuration?.baseForegroundColor = .systemRed
            menu = UIMenu(
                title: failure.explanation,
                children: [
                    UIAction(
                        title: String(
                            localized: "Try Again", table: "ChatDelivery", bundle: .module,
                            comment: "Sends a failed chat reply again"),
                        image: UIImage(systemName: "arrow.clockwise")
                    ) { _ in actions.retry(reply) },
                    Self.edit(reply, actions),
                    UIAction(
                        title: String(
                            localized: "Delete", table: "ChatDelivery", bundle: .module,
                            comment: "Deletes a failed chat reply"),
                        image: UIImage(systemName: "trash"), attributes: .destructive
                    ) { _ in actions.discard(reply) },
                ])
        }
        isUserInteractionEnabled = menu != nil
        accessibilityTraits = menu == nil ? .staticText : .button
    }

    private static func edit(_ reply: Draft.ID, _ actions: Actions) -> UIAction {
        UIAction(
            title: String(
                localized: "Edit", table: "ChatDelivery", bundle: .module,
                comment: "Opens a scheduled or failed chat reply in the composer"),
            image: UIImage(systemName: "pencil")
        ) { _ in actions.edit(reply) }
    }

    /// Fades a bubble while its reply is on its way and brings it to full color once it goes. A reply just sent
    /// rises into place from the field below, as a chat's does; with Reduce Motion it only fades in.
    static func show(_ delivery: ChatTranscript.Delivery, on bubble: UIView, arriving: Bool) {
        let alpha = delivery.alpha
        guard arriving else {
            guard bubble.alpha != alpha else { return }
            UIView.animate(withDuration: 0.35, delay: 0, options: [.beginFromCurrentState, .allowUserInteraction]) {
                bubble.alpha = alpha
            }
            return
        }
        bubble.alpha = 0
        if !SystemAccessibility.reducesMotion {
            bubble.transform = CGAffineTransform(translationX: 0, y: 28).scaledBy(x: 0.92, y: 0.92)
        }
        UIView.animate(
            springDuration: 0.5, bounce: Motion.bounce(0.25), initialSpringVelocity: 0, delay: 0,
            options: [.allowUserInteraction]
        ) {
            bubble.alpha = alpha
            bubble.transform = .identity
        }
    }
}
