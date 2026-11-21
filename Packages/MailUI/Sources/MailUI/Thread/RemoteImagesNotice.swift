import MailCore
import UIKit

/// Under a message's header while its remote images are blocked: Load Remote Images loads them this once, and the
/// menu beside it trusts the sender or their domain, naming which, so those images always load on this device.
final class RemoteImagesNotice: UIView {
    var onLoad: (() -> Void)?
    var onTrust: ((ImageTrustRule) -> Void)?

    private let load = ConfiguredButton(configuration: .gray())
    private let more = ConfiguredButton(configuration: .gray())

    override init(frame: CGRect) {
        super.init(frame: frame)
        var loadStyle = UIButton.Configuration.gray()
        loadStyle.cornerStyle = .capsule
        loadStyle.image = UIImage(systemName: "photo.badge.arrow.down")
        loadStyle.imagePadding = 6
        loadStyle.title = String(
            localized: "Load Remote Images", table: "Thread", bundle: .module, comment: "Shows blocked remote content")
        loadStyle.buttonSize = .small
        load.configuration = loadStyle
        load.addAction(UIAction { [weak self] _ in self?.onLoad?() }, for: .primaryActionTriggered)

        var moreStyle = UIButton.Configuration.gray()
        moreStyle.cornerStyle = .capsule
        moreStyle.image = UIImage(systemName: "ellipsis")
        moreStyle.buttonSize = .small
        more.configuration = moreStyle
        more.showsMenuAsPrimaryAction = true
        more.accessibilityLabel = String(
            localized: "More Image Options", table: "RemoteImages", bundle: .module,
            comment: "Accessibility label of the menu beside Load Remote Images")

        let row = UIStackView(arrangedSubviews: [load, more, UIView()])
        row.spacing = 8
        row.alignment = .center
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    /// Offers the rules `ImageTrustRule.offers(for:)` made from the sender; with none, as for a message without a
    /// sender address, only loading once.
    func configure(offers: [ImageTrustRule]) {
        more.isHidden = offers.isEmpty
        more.menu = UIMenu(
            children: offers.map { rule in Self.trustAction(rule) { [weak self] in self?.onTrust?(rule) } })
    }

    /// One choice in the menu. Its subtitle names the address or domain it trusts, since a display name can be
    /// anyone's.
    static func trustAction(_ rule: ImageTrustRule, perform: @escaping () -> Void) -> UIAction {
        let title =
            switch rule.kind {
            case .sender:
                String(
                    localized: "Always Load from This Sender", table: "RemoteImages", bundle: .module,
                    comment: "Menu item: always load remote images in mail from this message's sender")
            case .domain:
                String(
                    localized: "Always Load from This Domain", table: "RemoteImages", bundle: .module,
                    comment: "Menu item: always load remote images in mail from any address at the sender's domain")
            }
        let image = rule.kind == .sender ? "person.crop.circle.badge.checkmark" : "building.2"
        return UIAction(title: title, subtitle: rule.value, image: UIImage(systemName: image)) { _ in perform() }
    }
}
