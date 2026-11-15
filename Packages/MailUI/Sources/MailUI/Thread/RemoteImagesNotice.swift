import UIKit

/// Under a message's header while its remote images are blocked: Load Remote Images loads them this once, and the
/// menu beside it trusts the sender, naming the address, so their images always load on this device.
final class RemoteImagesNotice: UIView {
    var onLoad: (() -> Void)?
    var onTrustSender: (() -> Void)?

    private let load = UIButton(configuration: .gray())
    private let more = UIButton(configuration: .gray())

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

    /// Offers to trust `sender`; a message without a sender address offers only to load once.
    func configure(sender: String) {
        more.isHidden = sender.isEmpty
        more.menu = UIMenu(children: [Self.trustAction(sender: sender) { [weak self] in self?.onTrustSender?() }])
    }

    /// The menu's one choice. Its subtitle names the address it trusts, since a display name can be anyone's.
    static func trustAction(sender: String, perform: @escaping () -> Void) -> UIAction {
        UIAction(
            title: String(
                localized: "Always Load from This Sender", table: "RemoteImages", bundle: .module,
                comment: "Menu item: always load remote images in mail from this message's sender"),
            subtitle: sender, image: UIImage(systemName: "checkmark.shield")
        ) { _ in perform() }
    }
}
