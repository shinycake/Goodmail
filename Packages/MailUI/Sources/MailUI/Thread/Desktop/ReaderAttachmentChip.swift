import MailCore
import UIKit

/// An attachment's capsule. Touch opens it with a tap. On a desktop window a click selects it, as in the Finder: it
/// takes the keyboard and an outline, Space or ⌘Y previews it in Quick Look, a double-click opens it, and the context
/// menu offers Save to Downloads. Whether it is selected is whether it is the first responder.
final class ReaderAttachmentChip: UIButton {
    let attachment: Attachment
    /// Opens the attachment's preview.
    var onOpen: (() -> Void)?
    var onSave: (() -> Void)?

    init(attachment: Attachment) {
        self.attachment = attachment
        super.init(frame: .zero)
        configuration = AttachmentListView.configuration(for: attachment)
        addAction(UIAction { [weak self] _ in self?.clicked() }, for: .primaryActionTriggered)
        let double = UITapGestureRecognizer(target: self, action: #selector(doubleClicked))
        double.numberOfTapsRequired = 2
        addGestureRecognizer(double)
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (chip: ReaderAttachmentChip, _) in
            chip.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    private var isDesktop: Bool { traitCollection.interactionStyle == .desktop }

    func quickLook() {
        onOpen?()
    }

    private func clicked() {
        if isDesktop { _ = becomeFirstResponder() } else { onOpen?() }
    }

    @objc private func doubleClicked() {
        if isDesktop { onOpen?() }
    }

    override var canBecomeFirstResponder: Bool { isDesktop }

    /// Space, as in the Finder. ⌘Y is the menu bar's Quick Look command, which finds the selected chip.
    override var keyCommands: [UIKeyCommand]? {
        let space = UIKeyCommand(input: " ", modifierFlags: [], action: #selector(quickLookFromKeyboard))
        space.wantsPriorityOverSystemBehavior = true
        return [space]
    }

    @objc private func quickLookFromKeyboard() {
        quickLook()
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became { setNeedsLayout() }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { setNeedsLayout() }
        return resigned
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.borderWidth = isFirstResponder ? 2 : 0
        layer.borderColor = tintColor.resolvedColor(with: traitCollection).cgColor
        layer.cornerRadius = bounds.height / 2
    }

    /// A button is its own context menu delegate. Only a desktop window gets this menu.
    override func contextMenuInteraction(
        _ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard isDesktop else {
            return super.contextMenuInteraction(interaction, configurationForMenuAtLocation: location)
        }
        _ = becomeFirstResponder()
        return UIContextMenuConfiguration(actionProvider: { [weak self] _ in
            UIMenu(children: [
                UIAction(
                    title: String(
                        localized: "Quick Look", table: "Thread", bundle: .module,
                        comment: "Context menu of an attachment: previews it"),
                    image: UIImage(systemName: "eye")
                ) { _ in self?.quickLook() },
                UIAction(
                    title: String(
                        localized: "Save to Downloads", table: "Thread", bundle: .module,
                        comment: "Context menu of an attachment: copies it to the Downloads folder"),
                    image: UIImage(systemName: "arrow.down.circle")
                ) { _ in self?.onSave?() },
            ])
        })
    }
}
