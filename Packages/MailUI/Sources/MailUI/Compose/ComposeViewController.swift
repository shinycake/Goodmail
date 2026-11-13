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
    let bodyView = UITextView(usingTextLayoutManager: true)
    let formattingBar = FormattingBar()
    let quoteLayout = QuoteLayout()
    private let quoteButton = UIButton(configuration: .gray())
    private let quoteLabel = UILabel()
    private var ccRow: UIView!
    private var bccRow: UIView!
    private var toRow: UIView!
    private var fields: UIStackView!
    /// People matching the recipient being typed, shown under its field.
    private let suggestionList = UIStackView()
    /// Looking up the people for the last keystroke; a newer keystroke replaces it.
    private var suggestionLookup: Task<Void, Never>?
    private let attachmentsView = ComposeAttachmentsView()
    private let sendItem = UIBarButtonItem()
    private let fromButton = UIButton(configuration: .plain())
    /// Photos and scans waiting to be turned into attachments, in the order they were taken.
    let captures = AsyncStream.makeStream(of: CapturedAttachment.Preparation.self)
    /// Prepares `captures` one at a time and attaches each. Cancelling it when the message closes stops the one in
    /// hand and every one waiting.
    var preparing: Task<Void, Never>?

    public init(viewModel: ComposeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        preparing = preparingCaptures()
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

        bodyView.font = bodyFont
        if !(viewModel.draft.body.plain ?? "").isEmpty {
            // A draft reopened after Undo or a failed send, or a new one with a signature.
            show(viewModel.draft.body)
        }
        bodyView.adjustsFontForContentSizeCategory = true
        bodyView.isScrollEnabled = false
        bodyView.allowsEditingTextAttributes = true
        configureFormatting()
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
        if viewModel.canChangeSender { stack.insertArrangedSubview(fromRow(), at: 0) }
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

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed || navigationController?.isBeingDismissed == true {
            captures.continuation.finish()
            preparing?.cancel()
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Replies start in the body; new messages and forwards with who they're for.
        (viewModel.draft.to.isEmpty ? toField : bodyView as UIResponder).becomeFirstResponder()
        // A fresh draft starts at the top, above any signature; a restored one where the writer left off.
        let start = viewModel.isRestored ? bodyView.attributedText.length : 0
        bodyView.selectedRange = NSRange(location: start, length: 0)
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
        // Touching and holding Send offers to send later.
        sendItem.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in completion(self?.sendLaterItems() ?? []) }
        ])
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
                UIAction { [weak self] _ in
                    self?.suggestionLookup?.cancel()
                    self?.suggestionList.isHidden = true
                }, for: .editingDidEnd)
        }
    }

    /// Looks up the people matching what is being typed in `field` and lists them right under it.
    private func showSuggestions(for field: UITextField) {
        suggestionLookup?.cancel()
        let typed = field.text ?? ""
        suggestionLookup = Task { [weak self, weak field] in
            guard let self, let field else { return }
            let contacts = await viewModel.suggestions(for: typed)
            guard !Task.isCancelled else { return }
            list(contacts, under: field)
        }
    }

    /// Shows `contacts` under `field`. A tap completes the recipient.
    private func list(_ contacts: [Contact], under field: UITextField) {
        for view in suggestionList.arrangedSubviews { view.removeFromSuperview() }
        suggestionList.removeFromSuperview()
        let row = [toField: toRow, ccField: ccRow, bccField: bccRow][field] ?? nil
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

    /// The account the message goes from, as a menu of the others.
    private func fromRow() -> UIView {
        let label = UILabel()
        label.text = String(localized: "From:", bundle: .module, comment: "Compose field label")
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        fromButton.configuration?.contentInsets = .zero
        fromButton.configuration?.baseForegroundColor = .label
        fromButton.configuration?.image = UIImage(systemName: "chevron.up.chevron.down")
        fromButton.configuration?.imagePlacement = .trailing
        fromButton.configuration?.imagePadding = 4
        fromButton.configuration?.preferredSymbolConfigurationForImage = UIImage.SymbolConfiguration(
            textStyle: .footnote)
        fromButton.showsMenuAsPrimaryAction = true
        fromButton.changesSelectionAsPrimaryAction = false
        // Sized to the address, so the menu opens from it rather than from the far edge.
        fromButton.setContentHuggingPriority(.required, for: .horizontal)
        updateFrom()
        let line = UIStackView(arrangedSubviews: [label, fromButton, UIView()])
        line.spacing = 6
        line.alignment = .firstBaseline
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

    private func updateFrom() {
        var title = AttributedString(viewModel.accountEmail)
        title.font = .preferredFont(forTextStyle: .body)
        fromButton.configuration?.attributedTitle = title
        fromButton.accessibilityLabel = String(
            localized: "From: \(viewModel.accountEmail)", bundle: .module,
            comment: "VoiceOver: the account the message is sent from")
        fromButton.menu = UIMenu(
            options: .singleSelection,
            children: viewModel.senders.map { account in
                // No image: the address gets the menu's whole width rather than wrapping.
                UIAction(title: account.email, state: account.email == viewModel.accountEmail ? .on : .off) {
                    [weak self] _ in self?.changeSender(to: account)
                }
            })
    }

    private func changeSender(to account: Account) {
        if let body = viewModel.changeSender(to: account, body: body) {
            show(body)
            bodyView.selectedRange = NSRange(location: 0, length: 0)
        }
        updateFrom()
    }

    /// The quoted conversation, folded behind a control, as in the reader.
    private func quoteSection() -> UIView {
        var configuration = UIButton.Configuration.gray()
        configuration.cornerStyle = .capsule
        configuration.title = "•••"
        configuration.buttonSize = .small
        quoteButton.configuration = configuration
        quoteLabel.text = viewModel.draft.quote?.plain
        quoteLabel.numberOfLines = 0
        quoteLabel.font = .preferredFont(forTextStyle: .subheadline)
        quoteLabel.textColor = .secondaryLabel
        quoteLabel.adjustsFontForContentSizeCategory = true
        quoteLabel.isHidden = true
        updateQuoteButtonLabel()
        quoteButton.addAction(
            UIAction { [weak self] _ in
                guard let self else { return }
                UIView.animate(springDuration: 0.3) { self.quoteLabel.isHidden.toggle() }
                updateQuoteButtonLabel()
            }, for: .primaryActionTriggered)
        let buttonRow = UIStackView(arrangedSubviews: [quoteButton, UIView()])
        let section = UIStackView(arrangedSubviews: [buttonRow, quoteLabel])
        section.axis = .vertical
        section.spacing = 10
        return section
    }

    /// The fold says what it will do next, since its "•••" reads the same either way.
    private func updateQuoteButtonLabel() {
        quoteButton.accessibilityLabel =
            quoteLabel.isHidden
            ? String(localized: "Show Quoted Text", bundle: .module, comment: "Accessibility label of the fold")
            : String(localized: "Hide Quoted Text", bundle: .module, comment: "Accessibility label of the open fold")
    }

    private func fieldChanged() {
        viewModel.toText = toField.text ?? ""
        viewModel.ccText = ccField.text ?? ""
        viewModel.bccText = bccField.text ?? ""
        viewModel.subject = subjectField.text ?? ""
        updateSendEnabled()
    }

    private func show(_ body: MessageBody) {
        bodyView.attributedText = RichText(body).attributedString(font: bodyFont)
        bodyView.typingAttributes = [.font: bodyFont]
    }

    func updateSendEnabled() {
        sendItem.isEnabled = viewModel.canSend
        // A swipe down asks before losing what was written.
        navigationController?.isModalInPresentation = viewModel.hasChanges(body: body)
    }

    private var body: MessageBody {
        RichText(bodyView.attributedText ?? NSAttributedString()).messageBody
    }

    /// Adds a picked file, or explains why it can't go.
    func add(_ attachment: DraftAttachment) {
        guard viewModel.attach(attachment) else { return tooLarge() }
        attachmentsView.show(viewModel.attachments)
        updateSendEnabled()
    }

    private func send(at time: SendTime = .now) {
        fieldChanged()
        viewModel.send(body: body, at: time)
        dismiss(animated: true)
    }

    /// The times on offer now, then a picker for any other.
    private func sendLaterItems() -> [UIMenuElement] {
        let choices = LaterTime.sendChoices(at: .now).map { choice in
            UIAction(title: choice.title, image: UIImage(systemName: choice.symbol)) { [weak self] _ in
                self?.send(at: .at(choice.date))
            }
        }
        let pick = UIAction(
            title: String(localized: "Choose a Time…", bundle: .module, comment: "Picks a later time from a calendar"),
            image: UIImage(systemName: "calendar")
        ) { [weak self] _ in self?.pickSendTime() }
        return [
            UIMenu(
                title: String(localized: "Send Later", bundle: .module, comment: "Menu of times to send a message"),
                options: .displayInline, children: choices + [pick])
        ]
    }

    private func pickSendTime() {
        LaterPickerViewController.present(
            from: self,
            title: String(localized: "Send Later", bundle: .module, comment: "Menu of times to send a message"),
            actionTitle: String(
                localized: "Schedule", bundle: .module, comment: "Schedules the message for the picked time"),
            initial: LaterTime.sendChoices(at: .now).first?.date
        ) { [weak self] date in self?.send(at: .at(date)) }
    }

    private func cancel() {
        fieldChanged()
        guard viewModel.hasChanges(body: body) else { return dismiss(animated: true) }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(
            UIAlertAction(
                title: String(localized: "Delete Draft", bundle: .module, comment: "Discards the message"),
                style: .destructive
            ) { [weak self] _ in
                self?.viewModel.deleteDraft()
                self?.dismiss(animated: true)
            })
        if viewModel.canSaveDraft {
            sheet.addAction(
                UIAlertAction(
                    title: String(localized: "Save Draft", bundle: .module, comment: "Keeps the message in Drafts"),
                    style: .default
                ) { [weak self] _ in
                    guard let self else { return }
                    viewModel.saveDraft(body: body)
                    dismiss(animated: true)
                })
        }
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

    public func textView(
        _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
    ) -> Bool {
        guard text == "\n",
            let command = FormattingCommand.onReturn(
                in: textView.textStorage, selection: range, typingAttributes: textView.typingAttributes)
        else { return true }
        applyFormatting(command)
        return false
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        showFormatting()
    }

    public func presentationControllerDidAttemptToDismiss(_ presentationController: UIPresentationController) {
        cancel()
    }
}
