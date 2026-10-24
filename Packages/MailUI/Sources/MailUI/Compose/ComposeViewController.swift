import MailCore
import UIKit

/// Writing a message: recipients, subject, then the body as the page. The quoted conversation stays out of the way
/// below, and goes with the message.
public final class ComposeViewController: UIViewController {
    private let viewModel: ComposeViewModel
    private let scrollView = UIScrollView()
    private let toField = UITextField()
    private let ccField = UITextField()
    private let bccField = UITextField()
    private let subjectField = UITextField()
    private let bodyView = UITextView(usingTextLayoutManager: true)
    private let quoteButton = UIButton(configuration: .gray())
    private let quoteLabel = UILabel()
    private var ccRow: UIView!
    private var bccRow: UIView!
    private var toRow: UIView!
    private var fields: UIStackView!
    /// People matching the recipient being typed, shown under its field.
    private let suggestionList = UIStackView()
    private let attachmentsView = ComposeAttachmentsView()
    private let sendItem = UIBarButtonItem()

    public init(viewModel: ComposeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        configureNavigation()

        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        configure(toField, text: viewModel.toText, isAddress: true)
        configure(ccField, text: viewModel.ccText, isAddress: true)
        configure(bccField, text: viewModel.bccText, isAddress: true)
        configure(subjectField, text: viewModel.subject, isAddress: false)
        toField.accessibilityIdentifier = "compose.to"
        subjectField.accessibilityIdentifier = "compose.subject"

        bodyView.font = .preferredFont(forTextStyle: .body)
        if let font = bodyView.font, !(viewModel.draft.body.plain ?? "").isEmpty {
            // A draft reopened after Undo or a failed send.
            bodyView.attributedText = RichTextSerializer.attributedText(from: viewModel.draft.body, font: font)
            bodyView.typingAttributes = [.font: font]
        }
        bodyView.adjustsFontForContentSizeCategory = true
        bodyView.isScrollEnabled = false
        bodyView.allowsEditingTextAttributes = true
        bodyView.textContainerInset = UIEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        bodyView.textContainer.lineFragmentPadding = 0
        bodyView.delegate = self
        bodyView.accessibilityIdentifier = "compose.body"
        bodyView.accessibilityLabel = String(localized: "Message", bundle: .module, comment: "The body field")

        let showsCc = !viewModel.ccText.isEmpty || !viewModel.bccText.isEmpty
        ccRow = row(String(localized: "Cc:", bundle: .module, comment: "Compose field label"), ccField)
        bccRow = row(String(localized: "Bcc:", bundle: .module, comment: "Compose field label"), bccField)
        ccRow.isHidden = !showsCc
        bccRow.isHidden = !showsCc
        toRow = row(
            String(localized: "To:", bundle: .module, comment: "Compose field label"), toField, ccToggle: !showsCc)
        let stack = UIStackView(arrangedSubviews: [
            toRow, ccRow, bccRow,
            row(String(localized: "Subject:", bundle: .module, comment: "Compose field label"), subjectField),
            bodyView, attachmentsView,
        ])
        stack.axis = .vertical
        fields = stack
        stack.setCustomSpacing(16, after: attachmentsView)
        attachmentsView.show(viewModel.attachments)
        attachmentsView.onRemove = { [weak self] id in
            guard let self else { return }
            viewModel.removeAttachment(id)
            attachmentsView.show(viewModel.attachments)
            updateSendEnabled()
        }
        suggestionList.axis = .vertical
        suggestionList.isHidden = true
        if viewModel.draft.quote != nil { stack.addArrangedSubview(quoteSection()) }
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let readable = scrollView.readableContentGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: readable.trailingAnchor),
            bodyView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        updateSendEnabled()
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.presentationController?.delegate = self
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Replies start in the body; new messages and forwards with who they're for.
        (viewModel.draft.to.isEmpty ? toField : bodyView as UIResponder).becomeFirstResponder()
        // A fresh reply starts above the quote; a restored draft where the writer left off.
        if !viewModel.draft.to.isEmpty {
            bodyView.selectedRange = NSRange(location: bodyView.attributedText.length, length: 0)
        }
    }

    private func configureNavigation() {
        title =
            viewModel.isReply
            ? String(localized: "Reply", bundle: .module, comment: "Composer title for a reply")
            : String(localized: "New Message", bundle: .module, comment: "Composer title")
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak self] _ in self?.cancel() })
        sendItem.image = UIImage(systemName: "arrow.up")
        sendItem.style = .prominent
        sendItem.accessibilityLabel = String(localized: "Send", bundle: .module, comment: "Sends the message")
        sendItem.primaryAction = UIAction(
            title: String(localized: "Send", bundle: .module, comment: "Sends the message"),
            image: UIImage(systemName: "arrow.up")
        ) { [weak self] _ in self?.send() }
        navigationItem.rightBarButtonItems = [sendItem, attachItem()]
    }

    private func configure(_ field: UITextField, text: String, isAddress: Bool) {
        field.text = text
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        if isAddress {
            field.keyboardType = .emailAddress
            field.textContentType = .emailAddress
            field.autocapitalizationType = .none
            field.autocorrectionType = .no
        }
        field.addAction(
            UIAction { [weak self, weak field] _ in
                guard let self, let field else { return }
                fieldChanged()
                if isAddress { showSuggestions(for: field) }
            }, for: .editingChanged)
        if isAddress {
            field.addAction(
                UIAction { [weak self] _ in self?.suggestionList.isHidden = true }, for: .editingDidEnd)
        }
    }

    /// Lists the people matching what is being typed in `field` right under it. A tap completes the recipient.
    private func showSuggestions(for field: UITextField) {
        for view in suggestionList.arrangedSubviews { view.removeFromSuperview() }
        suggestionList.removeFromSuperview()
        let row = [toField: toRow, ccField: ccRow, bccField: bccRow][field] ?? nil
        let contacts = viewModel.suggestions(for: field.text ?? "")
        guard !contacts.isEmpty, let row, let index = fields.arrangedSubviews.firstIndex(of: row) else {
            suggestionList.isHidden = true
            return
        }
        for contact in contacts {
            var configuration = UIButton.Configuration.plain()
            configuration.title = contact.name ?? contact.address
            configuration.subtitle = contact.name == nil ? nil : contact.address
            configuration.titleAlignment = .leading
            configuration.baseForegroundColor = .label
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0)
            configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
                var attributes = $0
                attributes.foregroundColor = .secondaryLabel
                return attributes
            }
            let button = UIButton(
                configuration: configuration,
                primaryAction: UIAction { [weak self, weak field] _ in
                    guard let self, let field else { return }
                    field.text = ComposeViewModel.completing(field.text ?? "", with: contact)
                    fieldChanged()
                    suggestionList.isHidden = true
                })
            button.contentHorizontalAlignment = .leading
            suggestionList.addArrangedSubview(button)
        }
        fields.insertArrangedSubview(suggestionList, at: index + 1)
        suggestionList.isHidden = false
    }

    private func row(_ title: String, _ field: UITextField, ccToggle: Bool = false) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        field.accessibilityLabel = title
        let line = UIStackView(arrangedSubviews: [label, field])
        line.spacing = 6
        line.alignment = .firstBaseline
        if ccToggle {
            let toggle = UIButton(configuration: .plain())
            toggle.configuration?.title = String(localized: "Cc/Bcc", bundle: .module, comment: "Shows Cc and Bcc")
            toggle.configuration?.contentInsets = .zero
            toggle.setContentHuggingPriority(.required, for: .horizontal)
            // A long recipient line scrolls in its field rather than squeezing the button.
            toggle.setContentCompressionResistancePriority(.required, for: .horizontal)
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            toggle.addAction(
                UIAction { [weak self, weak toggle] _ in
                    toggle?.isHidden = true
                    UIView.animate(springDuration: 0.3) {
                        self?.ccRow.isHidden = false
                        self?.bccRow.isHidden = false
                    }
                    self?.ccField.becomeFirstResponder()
                }, for: .primaryActionTriggered)
            line.addArrangedSubview(toggle)
        }
        let separator = UIView()
        separator.backgroundColor = .separator
        let container = UIStackView(arrangedSubviews: [line, separator])
        container.axis = .vertical
        container.spacing = 12
        container.isLayoutMarginsRelativeArrangement = true
        container.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 12, leading: 0, bottom: 0, trailing: 0)
        separator.heightAnchor.constraint(equalToConstant: 1 / max(1, traitCollection.displayScale)).isActive = true
        return container
    }

    /// The quoted conversation, folded behind a control, as in the reader.
    private func quoteSection() -> UIView {
        var configuration = UIButton.Configuration.gray()
        configuration.cornerStyle = .capsule
        configuration.title = "•••"
        configuration.buttonSize = .small
        quoteButton.configuration = configuration
        quoteButton.accessibilityLabel = String(
            localized: "Show Quoted Text", bundle: .module, comment: "Accessibility label of the fold")
        quoteLabel.text = viewModel.draft.quote?.plain
        quoteLabel.numberOfLines = 0
        quoteLabel.font = .preferredFont(forTextStyle: .subheadline)
        quoteLabel.textColor = .secondaryLabel
        quoteLabel.adjustsFontForContentSizeCategory = true
        quoteLabel.isHidden = true
        quoteButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                UIView.animate(springDuration: 0.3) { self.quoteLabel.isHidden.toggle() }
            }, for: .primaryActionTriggered)
        let buttonRow = UIStackView(arrangedSubviews: [quoteButton, UIView()])
        let section = UIStackView(arrangedSubviews: [buttonRow, quoteLabel])
        section.axis = .vertical
        section.spacing = 10
        return section
    }

    private func fieldChanged() {
        viewModel.toText = toField.text ?? ""
        viewModel.ccText = ccField.text ?? ""
        viewModel.bccText = bccField.text ?? ""
        viewModel.subject = subjectField.text ?? ""
        updateSendEnabled()
    }

    private func updateSendEnabled() {
        sendItem.isEnabled = viewModel.canSend
        // A swipe down asks before losing what was written.
        navigationController?.isModalInPresentation = viewModel.hasChanges(body: body)
    }

    private var body: MessageBody {
        RichTextSerializer.body(from: bodyView.attributedText ?? NSAttributedString())
    }

    /// Adds a picked file, or explains why it can't go.
    func add(_ attachment: DraftAttachment) {
        guard viewModel.attach(attachment) else { return tooLarge() }
        attachmentsView.show(viewModel.attachments)
        updateSendEnabled()
    }

    private func send() {
        fieldChanged()
        viewModel.send(body: body)
        dismiss(animated: true)
    }

    private func cancel() {
        fieldChanged()
        guard viewModel.hasChanges(body: body) else { return dismiss(animated: true) }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(
            UIAlertAction(
                title: String(localized: "Delete Draft", bundle: .module, comment: "Discards the message"),
                style: .destructive
            ) { [weak self] _ in self?.dismiss(animated: true) })
        sheet.addAction(
            UIAlertAction(
                title: String(localized: "Keep Editing", bundle: .module, comment: "Returns to the message"),
                style: .cancel))
        sheet.popoverPresentationController?.sourceItem = navigationItem.leftBarButtonItem
        present(sheet, animated: true)
    }
}

extension ComposeViewController: UITextViewDelegate, UIAdaptivePresentationControllerDelegate {
    public func textViewDidChange(_ textView: UITextView) {
        updateSendEnabled()
    }

    public func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        cancel()
    }
}
