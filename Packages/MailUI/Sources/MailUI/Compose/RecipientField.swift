import MailCore
import UIKit

/// A To, Cc or Bcc line: its label, the recipients as tokens wrapping onto as many lines as they need, then the
/// text being typed. It shows a `RecipientEntry` and reports what the writer does as `Intent`s; the composer keeps
/// the entry and shows it back.
final class RecipientField: UIView {
    enum Intent {
        case type(String)
        /// Delete with nothing typed.
        case deleteBackward
        case select(Int)
        case remove(Int)
        case move(DraggedRecipient, to: Recipients.Role, at: Int)
        /// Return: makes tokens of what is typed, or goes on to the next field when nothing is.
        case commit
        case endEditing
        /// Text dropped in from another app.
        case drop(String)
    }

    let role: Recipients.Role
    var onIntent: (Intent) -> Void = { _ in }
    /// The field's own menu entries for a token: moving it to the other fields.
    var moveTargets: [(role: Recipients.Role, title: String)] = []

    private let label = UILabel()
    let textField = RecipientTextField()
    private var tokens: [RecipientToken] = []
    /// Sits at the trailing end of the first line, such as the Cc/Bcc button.
    private var accessory: UIView?
    private var height: CGFloat = 0
    private static let lineSpacing: CGFloat = 6
    private static let spacing: CGFloat = 6
    /// The narrowest the typing space gets before it moves to a line of its own.
    private static let minimumTypingWidth: CGFloat = 80

    init(role: Recipients.Role, title: String, accessory: UIView? = nil) {
        self.role = role
        self.accessory = accessory
        super.init(frame: .zero)
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        label.isAccessibilityElement = false
        addSubview(label)
        if let accessory { addSubview(accessory) }

        textField.font = .preferredFont(forTextStyle: .body)
        textField.adjustsFontForContentSizeCategory = true
        textField.keyboardType = .emailAddress
        textField.textContentType = .emailAddress
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.returnKeyType = .next
        textField.accessibilityLabel = title
        textField.delegate = self
        textField.onDeleteWhenEmpty = { [weak self] in self?.onIntent(.deleteBackward) }
        textField.addAction(
            UIAction { [weak self] _ in self?.onIntent(.type(self?.textField.text ?? "")) }, for: .editingChanged)
        textField.addAction(UIAction { [weak self] _ in self?.onIntent(.endEditing) }, for: .editingDidEnd)
        addSubview(textField)
        addInteraction(UIDropInteraction(delegate: self))
        // A tap on the field's empty space types after the tokens.
        let tap = UITapGestureRecognizer(target: textField, action: #selector(becomeFirstResponder))
        tap.delegate = self
        addGestureRecognizer(tap)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    func removeAccessory() {
        accessory?.removeFromSuperview()
        accessory = nil
        setNeedsLayout()
        invalidateIntrinsicContentSize()
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool { textField.becomeFirstResponder() }

    override var isFirstResponder: Bool { textField.isFirstResponder }

    func show(_ entry: RecipientEntry) {
        if tokens.map(\.contact) != entry.contacts {
            for token in tokens { token.removeFromSuperview() }
            tokens = entry.contacts.enumerated().map { index, contact in
                let token = RecipientToken(contact: contact, menu: menu(for: contact, at: index))
                token.addAction(
                    UIAction { [weak self] _ in self?.onIntent(.select(index)) }, for: .menuActionTriggered)
                let drag = UIDragInteraction(delegate: self)
                drag.isEnabled = true
                token.addInteraction(drag)
                addSubview(token)
                return token
            }
            setNeedsLayout()
            invalidateIntrinsicContentSize()
        }
        for (index, token) in tokens.enumerated() { token.isSelected = entry.selected == index }
        if textField.text != entry.typed { textField.text = entry.typed }
        // While a token is selected the caret hides, as the next Delete is the token's.
        textField.tintColor = entry.selected == nil ? nil : .clear
    }

    private func menu(for contact: Contact, at index: Int) -> UIMenu {
        let copy = UIAction(
            title: String(
                localized: "Copy Address", table: "Compose", bundle: .module,
                comment: "Recipient menu: copies the address"),
            image: UIImage(systemName: "doc.on.doc")
        ) { _ in UIPasteboard.general.string = contact.address }
        let moves = moveTargets.map { target in
            UIAction(title: target.title, image: UIImage(systemName: "arrow.up.arrow.down")) { [weak self] _ in
                guard let self else { return }
                onIntent(.move(DraggedRecipient(role: role, index: index), to: target.role, at: .max))
            }
        }
        let remove = UIAction(
            title: String(
                localized: "Remove", table: "Compose", bundle: .module,
                comment: "Takes a file or a recipient off the message"
            ),
            image: UIImage(systemName: "xmark"), attributes: .destructive
        ) { [weak self] _ in self?.onIntent(.remove(index)) }
        // The title is the address, which the pill itself leaves out.
        return UIMenu(
            title: contact.name == nil ? "" : contact.address,
            children: [
                UIMenu(options: .displayInline, children: [copy] + moves),
                UIMenu(options: .displayInline, children: [remove]),
            ])
    }

    // MARK: Layout

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: arrangement(width: bounds.width).height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let layout = arrangement(width: bounds.width)
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        for (view, frame) in layout.frames {
            // Laid out leading to trailing, then mirrored for right-to-left.
            view.frame =
                isRightToLeft
                ? CGRect(
                    x: bounds.width - frame.maxX, y: frame.minY, width: frame.width, height: frame.height) : frame
        }
        if layout.height != height {
            height = layout.height
            invalidateIntrinsicContentSize()
        }
    }

    /// Where each part goes for `width`, leading edge at zero: the label, then tokens filling lines, then the typing
    /// space, which takes what is left of its line or a line of its own. The accessory keeps the first line's end.
    private func arrangement(width: CGFloat) -> (frames: [(UIView, CGRect)], height: CGFloat) {
        guard width > 0 else { return ([], textField.intrinsicContentSize.height) }
        let lineHeight = max(
            textField.intrinsicContentSize.height, tokens.first?.intrinsicContentSize.height ?? 0,
            label.intrinsicContentSize.height)
        var frames: [(UIView, CGRect)] = []
        let accessorySize = accessory?.intrinsicContentSize ?? .zero
        var lineEnd = accessory == nil ? width : width - accessorySize.width - Self.spacing
        if let accessory {
            frames.append(
                (
                    accessory,
                    CGRect(
                        x: width - accessorySize.width, y: (lineHeight - accessorySize.height) / 2,
                        width: accessorySize.width, height: accessorySize.height)
                ))
        }
        let labelSize = label.intrinsicContentSize
        frames.append(
            (
                label,
                CGRect(x: 0, y: (lineHeight - labelSize.height) / 2, width: labelSize.width, height: labelSize.height)
            ))
        var x = labelSize.width + Self.spacing
        var y: CGFloat = 0
        func newLine() {
            x = 0
            y += lineHeight + Self.lineSpacing
            lineEnd = width
        }
        for token in tokens {
            let size = token.intrinsicContentSize
            let tokenWidth = min(size.width, width)
            if x + tokenWidth > lineEnd, x > 0 { newLine() }
            frames.append(
                (token, CGRect(x: x, y: y + (lineHeight - size.height) / 2, width: tokenWidth, height: size.height)))
            x += tokenWidth + Self.spacing
        }
        if lineEnd - x < Self.minimumTypingWidth { newLine() }
        frames.append((textField, CGRect(x: x, y: y, width: lineEnd - x, height: lineHeight)))
        return (frames, y + lineHeight)
    }

    /// Where a drop at `point` puts a token: before the first token it lands ahead of, else last.
    private func insertionIndex(at point: CGPoint) -> Int {
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        return tokens.firstIndex { token in
            let frame = token.frame
            guard point.y < frame.maxY + Self.lineSpacing / 2 else { return false }
            return point.y < frame.minY - Self.lineSpacing / 2
                || (isRightToLeft ? point.x > frame.midX : point.x < frame.midX)
        } ?? tokens.count
    }
}

extension RecipientField: UIGestureRecognizerDelegate {
    /// Only taps on the field itself, not on its tokens or the typing space.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.view === self || touch.view === label
    }
}

extension RecipientField: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        onIntent(.commit)
        return false
    }
}

extension RecipientField: UIDragInteractionDelegate, UIDropInteractionDelegate {
    func dragInteraction(_ interaction: UIDragInteraction, itemsForBeginning session: any UIDragSession) -> [UIDragItem]
    {
        guard let token = interaction.view as? RecipientToken, let index = tokens.firstIndex(of: token) else {
            return []
        }
        let item = UIDragItem(itemProvider: NSItemProvider(object: token.contact.typedForm as NSString))
        item.localObject = DraggedRecipient(role: role, index: index)
        return [item]
    }

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: any UIDropSession) -> Bool {
        session.canLoadObjects(ofClass: NSString.self)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: any UIDropSession)
        -> UIDropProposal
    {
        UIDropProposal(operation: session.localDragSession == nil ? .copy : .move)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: any UIDropSession) {
        let index = insertionIndex(at: session.location(in: self))
        if let dragged = session.items.first?.localObject as? DraggedRecipient {
            return onIntent(.move(dragged, to: role, at: index))
        }
        // UIKit calls this back on the main queue.
        _ = session.loadObjects(ofClass: NSString.self) { [weak self] strings in
            let text = strings.compactMap { $0 as? String }.joined(separator: ",")
            MainActor.assumeIsolated { self?.onIntent(.drop(text)) }
        }
    }
}
