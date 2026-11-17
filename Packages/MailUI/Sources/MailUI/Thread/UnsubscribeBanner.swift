import MailCore
import UIKit

/// A quiet line above a mailing list's message that offers to leave the list, then says how leaving went.
final class UnsubscribeBanner: UIView {
    /// Asked when the reader taps the button: Unsubscribe, Try Again, or Done once they finished on the list's page.
    var onAction: (() -> Void)?

    private let symbol = UIImageView()
    private let label = UILabel()
    private let button = UIButton(configuration: .tinted())
    private let spinner = UIActivityIndicatorView(style: .medium)
    private let row = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        accessibilityIdentifier = "unsubscribe-banner"

        symbol.image = UIImage(systemName: "envelope.badge.person.crop")
        symbol.tintColor = .secondaryLabel
        symbol.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .subheadline)
        symbol.setContentHuggingPriority(.required, for: .horizontal)
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        button.configuration?.buttonSize = .small
        button.configuration?.cornerStyle = .capsule
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.addAction(UIAction { [weak self] _ in self?.onAction?() }, for: .primaryActionTriggered)
        button.accessibilityIdentifier = "unsubscribe"
        spinner.hidesWhenStopped = true

        row.addArrangedSubview(symbol)
        row.addArrangedSubview(label)
        row.addArrangedSubview(spinner)
        row.addArrangedSubview(button)
        row.spacing = 10
        row.alignment = .center
        row.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)
        row.isLayoutMarginsRelativeArrangement = true
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in self.stackForSize() }
        stackForSize()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func configure(_ offer: UnsubscribeOffer.Offer, tint: UIColor) {
        let name = offer.list.displayName
        let (text, action): (String, String?) =
            switch offer.state {
            case .offered, .unsubscribing:
                (
                    String(
                        localized: "This message is from a mailing list.", table: "Unsubscribe", bundle: .module,
                        comment: "Banner above a newsletter's message"),
                    String(
                        localized: "Unsubscribe", table: "Unsubscribe", bundle: .module,
                        comment: "Button: leaves the mailing list")
                )
            case .unsubscribed:
                (
                    String(
                        localized: "You unsubscribed from \(name).", table: "Unsubscribe", bundle: .module,
                        comment: "Banner once the list has the request; the argument is the list’s sender"),
                    nil
                )
            case .pageOpened:
                (
                    String(
                        localized: "Finish unsubscribing from \(name) on the page that opened.",
                        table: "Unsubscribe", bundle: .module,
                        comment: "Banner after opening the list’s unsubscribe page; the argument is the sender"),
                    String(
                        localized: "Done", table: "Unsubscribe", bundle: .module,
                        comment: "Button: the reader finished unsubscribing on the list’s page")
                )
            case .failed:
                (
                    String(
                        localized: "Couldn’t unsubscribe from \(name).", table: "Unsubscribe", bundle: .module,
                        comment: "Banner when the unsubscribe request fails; the argument is the list’s sender"),
                    String(
                        localized: "Try Again", table: "Unsubscribe", bundle: .module,
                        comment: "Button: asks the list again")
                )
            }
        label.text = text
        button.configuration?.title = action
        button.tintColor = tint
        button.isHidden = action == nil || offer.state == .unsubscribing
        if offer.state == .unsubscribing { spinner.startAnimating() } else { spinner.stopAnimating() }
        symbol.image = UIImage(
            systemName: offer.state == .unsubscribed ? "checkmark.circle" : "envelope.badge.person.crop")
    }

    /// The button drops below the text at accessibility sizes, so neither is squeezed.
    private func stackForSize() {
        let large = traitCollection.preferredContentSizeCategory.isAccessibilityCategory
        row.axis = large ? .vertical : .horizontal
        row.alignment = large ? .leading : .center
    }
}

extension UIAlertController {
    /// Asks before leaving a list, saying what will happen: a request, a message from the reader, or a page.
    static func unsubscribe(
        _ offer: UnsubscribeOffer.Offer, accountEmail: String, confirm: @escaping () -> Void
    ) -> UIAlertController {
        let name = offer.list.displayName
        let message =
            switch offer.unsubscribe {
            case .oneClick:
                String(
                    localized: "\(name) will be asked to stop sending you mail.", table: "Unsubscribe",
                    bundle: .module, comment: "Unsubscribe alert, one-click lists; the argument is the list’s sender")
            case .mail:
                String(
                    localized: "A message asking \(name) to stop sending you mail will go from \(accountEmail).",
                    table: "Unsubscribe", bundle: .module,
                    comment: "Unsubscribe alert for lists left by email; the arguments are the sender and the account")
            case .page:
                String(
                    localized: "\(name)’s page will open in your browser to finish.", table: "Unsubscribe",
                    bundle: .module,
                    comment: "Unsubscribe alert for lists left on a web page; the argument is the sender")
            }
        let alert = UIAlertController(
            title: String(
                localized: "Unsubscribe?", table: "Unsubscribe", bundle: .module,
                comment: "Title of the alert before leaving a mailing list"),
            message: message, preferredStyle: .alert)
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "Cancel", table: "Unsubscribe", bundle: .module, comment: "Button: stays on the list"),
                style: .cancel))
        let unsubscribe = UIAlertAction(
            title: String(
                localized: "Unsubscribe", table: "Unsubscribe", bundle: .module,
                comment: "Button: leaves the mailing list"),
            style: .default
        ) { _ in confirm() }
        alert.addAction(unsubscribe)
        alert.preferredAction = unsubscribe
        return alert
    }
}
