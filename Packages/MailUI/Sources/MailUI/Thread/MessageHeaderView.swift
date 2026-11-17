import MailCore
import UIKit

/// The top of an open message, as Apple Mail shows it: who wrote and when, the sender's real address under the
/// name, where replies go when that's someone else, and who it went to. Details opens every recipient's address;
/// Hide folds them again. Tapping anywhere else folds the message.
final class MessageHeaderView: UIView {
    /// How much of the recipients shows.
    enum Detail {
        /// One line of names: "to me, Dana Levi".
        case names
        /// A row per field, with every address.
        case addresses
    }

    var onFold: (() -> Void)?

    private var detail = Detail.names
    private var shown: (header: MessageHeader, accountEmail: String)?
    private let avatar = MonogramView()
    private let sender = UILabel()
    private let date = UILabel()
    private let address = AddressLabel()
    private let replyTo = AddressLabel()
    private let names = UILabel()
    private let fields = UIStackView()
    private let toggle = MinimumTargetButton(configuration: .plain())
    private let identity: UIStackView
    private let recipientRow: UIStackView

    override init(frame: CGRect) {
        let top = UIStackView(arrangedSubviews: [sender, date])
        top.spacing = 8
        top.stacksVerticallyAtAccessibilitySizes()
        identity = UIStackView(arrangedSubviews: [top, address, replyTo])
        let recipients = UIStackView(arrangedSubviews: [names, fields])
        recipientRow = UIStackView(arrangedSubviews: [recipients, toggle])
        super.init(frame: frame)
        sender.font = .preferredFont(forTextStyle: .headline)
        sender.adjustsFontForContentSizeCategory = true
        date.font = .preferredFont(forTextStyle: .subheadline)
        date.textColor = .secondaryLabel
        date.adjustsFontForContentSizeCategory = true
        date.setContentHuggingPriority(.required, for: .horizontal)
        date.setContentCompressionResistancePriority(.required, for: .horizontal)
        names.font = .preferredFont(forTextStyle: .subheadline)
        names.textColor = .secondaryLabel
        names.adjustsFontForContentSizeCategory = true
        // Every name shows, on as many lines as it takes at the accessibility sizes.
        names.numberOfLines = 0
        identity.axis = .vertical
        identity.spacing = 1
        // VoiceOver reads who, when and from where as one button; double-tapping it folds the message.
        identity.isAccessibilityElement = true
        identity.accessibilityTraits = .button

        var toggleLook = UIButton.Configuration.plain()
        toggleLook.contentInsets = .zero
        toggleLook.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = UIFont.preferredFont(forTextStyle: .subheadline)
            return attributes
        }
        toggle.configuration = toggleLook
        toggle.setContentHuggingPriority(.required, for: .horizontal)
        toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
        toggle.addAction(UIAction { [weak self] _ in self?.switchDetail() }, for: .primaryActionTriggered)

        fields.axis = .vertical
        fields.spacing = 4
        recipients.axis = .vertical
        recipientRow.spacing = 8
        // Tops, not first baselines, which put Hide a line low beside the Hebrew fields. The button and the first
        // line share a font, so their text lines up.
        recipientRow.alignment = .top
        // At the accessibility sizes Details goes under the names, which then have the width to themselves.
        func stack(_ row: UIStackView) {
            row.axis =
                row.traitCollection.preferredContentSizeCategory.isAccessibilityCategory ? .vertical : .horizontal
        }
        stack(recipientRow)
        recipientRow.registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (row: UIStackView, _) in
            stack(row)
        }

        let column = UIStackView(arrangedSubviews: [identity, recipientRow])
        column.axis = .vertical
        column.spacing = 4
        let row = UIStackView(arrangedSubviews: [avatar, column])
        row.spacing = 12
        row.alignment = .top
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        // The Details button keeps its own taps; a tap anywhere else folds the message.
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(fold)))
        // The names line's attributed text carries its font, which doesn't scale on its own.
        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (view: MessageHeaderView, _) in
            view.showDetail()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func configure(_ header: MessageHeader, dateText: String, accountEmail: String, badge: MonogramView.Badge?) {
        shown = (header, accountEmail)
        sender.setContentText(header.sender.displayName, alignedToContent: false)
        date.text = dateText
        avatar.configure(name: header.sender.displayName, address: header.sender.address, badge: badge)
        address.show(header.senderAddress.map { [Contact(name: nil, address: $0)] } ?? [], style: .addresses)
        replyTo.show(header.replyTo, style: .replyTo)
        identity.accessibilityLabel = [header.sender.displayName, header.senderAddress, dateText, replyTo.text]
            .compactMap(\.self).joined(separator: ", ")
        identity.accessibilityCustomActions = [address, replyTo].compactMap(\.copyAction)
        identity.accessibilityUserInputLabels = [header.sender.displayName]
        showDetail()
    }

    private func switchDetail() {
        detail =
            switch detail {
            case .names: .addresses
            case .addresses: .names
            }
        showDetail()
    }

    private func showDetail() {
        guard let (header, accountEmail) = shown else { return }
        recipientRow.isHidden = header.fields.isEmpty
        switch detail {
        case .names:
            names.setContentText(Self.recipientsLine(header, accountEmail: accountEmail), alignedToContent: false)
            (names.isHidden, fields.isHidden) = (false, true)
            toggle.configuration?.title = String(
                localized: "Details", table: "Thread", bundle: .module,
                comment: "Shows every address a message went to")
            toggle.accessibilityLabel = String(
                localized: "Show Recipient Details", table: "Thread", bundle: .module,
                comment: "VoiceOver: shows every address a message went to")
        case .addresses:
            showFields(header.fields)
            (names.isHidden, fields.isHidden) = (true, false)
            toggle.configuration?.title = String(
                localized: "Hide", table: "Thread", bundle: .module,
                comment: "Folds a message's recipient addresses back into names")
            toggle.accessibilityLabel = String(
                localized: "Hide Recipient Details", table: "Thread", bundle: .module,
                comment: "VoiceOver: folds a message's recipient addresses back into names")
        }
    }

    /// "To" beside its people, then "Cc", "Bcc", their labels lined up in one column.
    private func showFields(_ shownFields: [MessageHeader.Field]) {
        for view in fields.arrangedSubviews { view.removeFromSuperview() }
        var firstKind: UILabel?
        for field in shownFields {
            let kind = UILabel()
            kind.font = .preferredFont(forTextStyle: .subheadline)
            kind.textColor = .secondaryLabel
            kind.adjustsFontForContentSizeCategory = true
            kind.text = Self.title(of: field.kind)
            kind.setContentHuggingPriority(.required, for: .horizontal)
            kind.setContentCompressionResistancePriority(.required, for: .horizontal)
            let people = AddressLabel()
            people.show(field.contacts, style: .people)
            let row = UIStackView(arrangedSubviews: [kind, people])
            row.spacing = 8
            row.alignment = .firstBaseline
            row.stacksVerticallyAtAccessibilitySizes()
            fields.addArrangedSubview(row)
            if let firstKind {
                kind.widthAnchor.constraint(equalTo: firstKind.widthAnchor).isActive = true
            } else {
                firstKind = kind
            }
            people.isAccessibilityElement = true
            people.accessibilityLabel = "\(kind.text ?? ""): \(people.text ?? "")"
        }
    }

    @objc private func fold() {
        onFold?()
    }

    private static func title(of kind: MessageHeader.Field.Kind) -> String {
        switch kind {
        case .to: String(localized: "To", table: "Thread", bundle: .module, comment: "A message's To field")
        case .cc: String(localized: "Cc", table: "Thread", bundle: .module, comment: "A message's Cc field")
        case .bcc: String(localized: "Bcc", table: "Thread", bundle: .module, comment: "A message's Bcc field")
        }
    }

    /// "to Dana Levi, me": the account's own address reads as "me".
    static func recipientsLine(_ header: MessageHeader, accountEmail: String) -> String {
        let me = String(localized: "me", table: "Thread", bundle: .module, comment: "The reader, in a recipient list")
        let names = header.recipients.map { contact in
            contact.address.caseInsensitiveCompare(accountEmail) == .orderedSame ? me : contact.displayName
        }
        return String(
            localized: "to \(names.formatted(.list(type: .and, width: .narrow)))", table: "Thread", bundle: .module,
            comment: "Recipients under the sender; the argument is a list of names")
    }
}

/// Addresses in a header, which a long press copies.
private final class AddressLabel: UILabel, UIContextMenuInteractionDelegate {
    enum Style {
        /// Bare addresses, as under the sender.
        case addresses
        /// "Replies go to x@y.com", with a reply arrow.
        case replyTo
        /// One per line, the name with its address beside it.
        case people
    }

    private var contacts: [Contact] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        font = .preferredFont(forTextStyle: .subheadline)
        adjustsFontForContentSizeCategory = true
        numberOfLines = 0
        isUserInteractionEnabled = true
        addInteraction(UIContextMenuInteraction(delegate: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func show(_ contacts: [Contact], style: Style) {
        self.contacts = contacts
        isHidden = contacts.isEmpty
        guard !contacts.isEmpty else {
            // No text either, so nothing of it reaches VoiceOver.
            attributedText = nil
            return
        }
        let text = NSMutableAttributedString(attributedString: Self.text(contacts, style: style, font: font))
        // Lines follow the interface's direction; the isolated addresses inside them keep their own.
        let paragraph = NSMutableParagraphStyle()
        let rightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        paragraph.baseWritingDirection = rightToLeft ? .rightToLeft : .leftToRight
        paragraph.alignment = rightToLeft ? .right : .left
        text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
        attributedText = text
    }

    /// Copies the addresses, for VoiceOver, which can't long-press a label inside a button.
    var copyAction: UIAccessibilityCustomAction? {
        guard !contacts.isEmpty else { return nil }
        return UIAccessibilityCustomAction(name: copyTitle) { [contacts] _ in
            UIPasteboard.general.string = contacts.map(\.address).joined(separator: ", ")
            return true
        }
    }

    private var copyTitle: String {
        contacts.count == 1
            ? String(
                localized: "Copy \(contacts[0].address)", table: "Thread", bundle: .module,
                comment: "Copies an email address from a message's header; the argument is the address")
            : String(
                localized: "Copy Addresses", table: "Thread", bundle: .module,
                comment: "Copies every email address in a header field")
    }

    func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !contacts.isEmpty else { return nil }
        let contacts = contacts
        return UIContextMenuConfiguration(actionProvider: { _ in
            UIMenu(
                children: contacts.map { contact in
                    UIAction(
                        title: String(
                            localized: "Copy \(contact.address)", table: "Thread", bundle: .module,
                            comment: "Copies an email address from a message's header; the argument is the address"),
                        image: UIImage(systemName: "doc.on.doc")
                    ) { _ in UIPasteboard.general.string = contact.address }
                })
        })
    }

    /// Addresses always read left to right, isolated so a Hebrew line around them keeps its order.
    private static func text(_ contacts: [Contact], style: Style, font: UIFont) -> NSAttributedString {
        let secondary: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.secondaryLabel]
        // A zero-width space after each "@" and "." lets a long address wrap there, where UIKit would otherwise
        // hyphenate it into something that reads as part of the address. Copying uses the address itself.
        let isolate = { (address: String) in
            let breakable = address.replacing("@", with: "@\u{200B}").replacing(".", with: ".\u{200B}")
            return "\u{2066}\(breakable)\u{2069}"
        }
        switch style {
        case .addresses:
            return NSAttributedString(
                string: contacts.map { isolate($0.address) }.joined(separator: ", "),
                attributes: secondary)
        case .replyTo:
            let line = NSMutableAttributedString()
            if let arrow = UIImage(systemName: "arrowshape.turn.up.left") {
                line.append(NSAttributedString(attachment: NSTextAttachment(image: arrow)))
                line.append(NSAttributedString(string: " "))
            }
            let list = contacts.map { isolate($0.address) }.formatted(.list(type: .and, width: .narrow))
            line.append(
                NSAttributedString(
                    string: String(
                        localized: "Replies go to \(list)", table: "Thread", bundle: .module,
                        comment: "Where a reply goes when that isn't the sender; the argument lists addresses"),
                    attributes: secondary))
            line.addAttribute(
                .foregroundColor, value: UIColor.secondaryLabel, range: NSRange(location: 0, length: line.length))
            return line
        case .people:
            let lines = NSMutableAttributedString()
            for (index, contact) in contacts.enumerated() {
                if index > 0 { lines.append(NSAttributedString(string: "\n")) }
                if contact.displayName != contact.address {
                    lines.append(
                        NSAttributedString(
                            string: "\(contact.displayName) ",
                            attributes: [.font: font, .foregroundColor: UIColor.label]))
                }
                lines.append(NSAttributedString(string: isolate(contact.address), attributes: secondary))
            }
            return lines
        }
    }
}
