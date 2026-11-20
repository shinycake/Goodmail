public import MailCore
public import UIKit

/// Writing a message: recipients, subject, then the body as the page. The quoted conversation stays out of the way
/// below, and goes with the message.
public final class ComposeViewController: UIViewController {
    let viewModel: ComposeViewModel
    private let scrollView = UIScrollView()
    /// The Cc/Bcc button sits at the end of the To line until those lines show.
    lazy var toField = recipientField(.to, accessory: startsWithCopyFields ? nil : ccToggle())
    lazy var ccField = recipientField(.cc)
    lazy var bccField = recipientField(.bcc)
    let subjectField = UITextField()
    let bodyView = BodyTextView(usingTextLayoutManager: true)
    let formattingBar = FormattingBar()
    /// The characters the edit being typed puts in, until its layout is settled.
    var typedRange: NSRange?
    private let quoteButton = UIButton(configuration: .gray())
    private let quoteLabel = UILabel()
    var ccRow: UIView!
    var bccRow: UIView!
    private var toRow: UIView!
    private var fields: UIStackView!
    /// People matching the recipient being typed, shown under its field.
    private let suggestionList = UIStackView()
    /// Looking up the people for the last keystroke; a newer keystroke replaces it.
    private var suggestionLookup: Task<Void, Never>?
    private let attachmentsView = ComposeAttachmentsView()
    private let sendItem = UIBarButtonItem()
    private let fromButton = UIButton(configuration: .plain())
    /// Takes files from Photos, Files, the camera and the scanner.
    lazy var picker = AttachmentPicker { [weak self] in self?.add($0) }
    /// Keeps the composer while it is minimized, moves it on and off the screen, and hears when it is done.
    weak var host: (any ComposerHost)?
    /// Moves the message into a window of its own, with it as written so far, where the device has windows; `nil`
    /// where it can't, as in a window that holds this message alone. Set before the composer shows.
    public var openInOwnWindow: ((Draft) -> Void)?
    /// The window scene the composer was shown in, kept while it is minimized and out of any window.
    private weak var scene: UIScene?

    public init(viewModel: ComposeViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        viewModel.didKeep = { [weak self] in
            guard let self else { return }
            host?.composerKept(self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        picker.presenter = self
        view.backgroundColor = .systemBackground
        configureNavigation()

        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        let showsCc = startsWithCopyFields
        configure(subjectField, text: viewModel.subject)
        toField.textField.accessibilityIdentifier = "compose.to"
        for field in [toField.textField, ccField.textField, bccField.textField, subjectField] {
            field.addAction(
                UIAction { [weak self, weak field] _ in self?.lastFocused = field }, for: .editingDidBegin)
        }
        subjectField.accessibilityIdentifier = "compose.subject"

        bodyView.font = bodyFont
        // Without a color, what is typed into an empty body draws black, even in Dark Mode.
        bodyView.typingAttributes = RichText.plainAttributes(font: bodyFont)
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
        bodyView.accessibilityLabel = String(
            localized: "Message", table: "Compose", bundle: .module, comment: "The body field")

        ccRow = row(ccField)
        bccRow = row(bccField)
        ccRow.isHidden = !showsCc
        bccRow.isHidden = !showsCc
        toRow = row(toField)
        let stack = UIStackView(arrangedSubviews: [
            toRow, ccRow, bccRow,
            row(
                labeled(
                    String(localized: "Subject:", table: "Compose", bundle: .module, comment: "Compose field label"),
                    subjectField)),
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
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: readable.trailingAnchor),
            bodyView.heightAnchor.constraint(greaterThanOrEqualToConstant: 160),
        ])
        updateScrollBottom()
        updateSendEnabled()
        // Leaving the app keeps the draft with the provider, in case the app isn't opened again.
        NotificationCenter.default.addObserver(
            self, selector: #selector(keepDraft(_:)), name: UIScene.didEnterBackgroundNotification, object: nil)
    }

    /// Only this composer's own scene going to the background keeps its draft, not another window's.
    @objc private func keepDraft(_ notification: Notification) {
        guard let scene = notification.object as? UIScene, scene === self.scene else { return }
        viewModel.keepNow(body: body)
    }

    /// A draft that already copies someone opens with the Cc and Bcc lines showing.
    private var startsWithCopyFields: Bool {
        !viewModel.recipients.cc.isEmpty || !viewModel.recipients.bcc.isEmpty
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scene = view.window?.windowScene
    }

    /// The card came to rest on the screen: writing starts, or goes on where it was.
    func didOpen() {
        switch showing {
        case .shown, .leaving: return
        case .minimized(let field):
            showing = .shown
            field?.becomeFirstResponder()
            return
        case .notYet:
            showing = .shown
        }
        // Replies start in the body; new messages and forwards with who they're for.
        (viewModel.draft.to.isEmpty ? toField : bodyView as UIResponder).becomeFirstResponder()
        // A fresh draft starts at the top, above any signature; a restored one where the writer left off.
        let start = viewModel.isRestored ? bodyView.attributedText.length : 0
        bodyView.selectedRange = NSRange(location: start, length: 0)
    }

    /// The field last written in, to write in again after minimizing.
    private weak var lastFocused: UIResponder?

    /// Where the composer stands on screen, so the cursor is placed the first time and kept after minimizing.
    private var showing = Showing.notYet {
        didSet { updateScrollBottom() }
    }

    /// The scroll view's bottom on the keyboard, or held on the safe area: one is active at a time
    /// (`updateScrollBottom`).
    private lazy var bottomOnKeyboard = scrollView.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
    private lazy var bottomHeld = scrollView.bottomAnchor.constraint(
        equalTo: view.safeAreaLayoutGuide.bottomAnchor)

    /// The message follows the keyboard while it is written in. Leaving or minimized, its card is scaled down and
    /// carried across the keyboard as it slides away, which would otherwise squeeze the message under its bar on the
    /// way, so its bottom holds still.
    private func updateScrollBottom() {
        let follows =
            switch showing {
            case .notYet, .shown: true
            case .leaving, .minimized: false
            }
        guard isViewLoaded else { return }
        // Off before on, so the two never conflict.
        (follows ? bottomHeld : bottomOnKeyboard).isActive = false
        (follows ? bottomOnKeyboard : bottomHeld).isActive = true
    }

    private enum Showing {
        case notYet
        case shown
        /// On its way off the screen from writing in that field, if any, and back to it if it stays.
        case leaving(UIResponder?)
        /// Minimized while writing in that field, if any, to write in again when it comes back.
        case minimized(UIResponder?)
    }

    private func configureNavigation() {
        title =
            viewModel.isReply
            ? String(localized: "Reply", table: "Compose", bundle: .module, comment: "Composer title for a reply")
            : String(localized: "New Message", table: "Compose", bundle: .module, comment: "Composer title")
        let close = UIBarButtonItem(systemItem: .close, primaryAction: UIAction { [weak self] _ in self?.cancel() })
        close.accessibilityIdentifier = "compose.close"
        navigationItem.leftBarButtonItems = [close] + [ownWindowItem()].compactMap(\.self)
        sendItem.image = UIImage(systemName: "arrow.up")
        sendItem.style = .prominent
        sendItem.accessibilityLabel = String(
            localized: "Send", table: "Compose", bundle: .module, comment: "Sends the message")
        sendItem.primaryAction = UIAction(
            title: String(localized: "Send", table: "Compose", bundle: .module, comment: "Sends the message"),
            image: UIImage(systemName: "arrow.up")
        ) { [weak self] _ in self?.send() }
        // Touching and holding Send offers to send later.
        sendItem.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in completion(self?.sendLaterItems() ?? []) }
        ])
        navigationItem.rightBarButtonItems = [sendItem, attachItem()]
    }

    private func configure(_ field: UITextField, text: String) {
        field.text = text
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.addAction(UIAction { [weak self] _ in self?.fieldChanged() }, for: .editingChanged)
    }

    /// Looks up the people matching what is being typed in `field` and lists them right under it.
    func showSuggestions(for field: RecipientField) {
        suggestionLookup?.cancel()
        let role = field.role
        suggestionLookup = Task { [weak self, weak field] in
            guard let self, let field else { return }
            let contacts = await viewModel.suggestions(for: role)
            guard !Task.isCancelled else { return }
            list(contacts, under: field)
        }
    }

    func hideSuggestions() {
        suggestionLookup?.cancel()
        suggestionList.isHidden = true
    }

    /// Shows `contacts` under `field`. A tap adds the recipient.
    private func list(_ contacts: [Contact], under field: RecipientField) {
        let shown = suggestionList.isHidden ? 0 : suggestionList.arrangedSubviews.count
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
                    edit(field) { $0.complete(with: contact) }
                    hideSuggestions()
                })
            button.contentHorizontalAlignment = .leading
            suggestionList.addArrangedSubview(button)
        }
        fields.insertArrangedSubview(suggestionList, at: index + 1)
        suggestionList.isHidden = false
        // The list appears under the field without moving VoiceOver off it, so say how many there are, after the
        // letter just typed is read and only when the number changes.
        if contacts.count != shown {
            SystemAccessibility.announce(
                String(
                    localized: "\(contacts.count) suggestions", table: "Compose", bundle: .module,
                    comment: "VoiceOver: how many recipients are suggested under the field"),
                queued: true)
        }
    }

    /// A field's title before it, on one line.
    private func labeled(_ title: String, _ field: UITextField) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = .secondaryLabel
        label.adjustsFontForContentSizeCategory = true
        label.setContentHuggingPriority(.required, for: .horizontal)
        // The field gives way to a long title, never the other way round.
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        field.accessibilityLabel = title
        let line = UIStackView(arrangedSubviews: [label, field])
        line.spacing = 6
        line.alignment = .firstBaseline
        return line
    }

    /// Shows Cc and Bcc, at the end of the To line until it's used.
    private func ccToggle() -> UIView {
        let toggle = UIButton(configuration: .plain())
        toggle.configuration?.title = String(
            localized: "Cc/Bcc", table: "Compose", bundle: .module, comment: "Shows Cc and Bcc")
        toggle.configuration?.contentInsets = .zero
        toggle.addAction(
            UIAction { [weak self] _ in
                self?.showCopyFields()
                self?.ccField.becomeFirstResponder()
            }, for: .primaryActionTriggered)
        return toggle
    }

    /// Shows the Cc and Bcc lines, which also takes the Cc/Bcc button away.
    func showCopyFields() {
        guard ccRow.isHidden else { return }
        toField.removeAccessory()
        UIView.animate(springDuration: 0.3) {
            self.ccRow.isHidden = false
            self.bccRow.isHidden = false
        }
    }

    /// A line of the header, with a hairline under it.
    private func row(_ line: UIView) -> UIView {
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
        label.text = String(localized: "From:", table: "Compose", bundle: .module, comment: "Compose field label")
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
        var title = AttributedString(viewModel.fromAddress)
        title.font = .preferredFont(forTextStyle: .body)
        fromButton.configuration?.attributedTitle = title
        fromButton.accessibilityLabel = String(
            localized: "From: \(viewModel.fromAddress)", table: "Compose", bundle: .module,
            comment: "VoiceOver: the account the message is sent from")
        fromButton.menu = UIMenu(
            options: .singleSelection,
            children: viewModel.senderChoices.map { address in
                // No image: the address gets the menu's whole width rather than wrapping. Under it, the account's
                // nickname, and an alias names its account.
                UIAction(
                    title: address.email,
                    subtitle: address.alias == nil ? address.account.nickname : address.account.title,
                    state: address.email == viewModel.fromAddress ? .on : .off
                ) { [weak self] _ in self?.changeSender(to: address) }
            })
    }

    private func changeSender(to address: SendingAddress) {
        if let body = viewModel.changeSender(to: address, body: body) {
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
            ? String(
                localized: "Show Quoted Text", table: "Compose", bundle: .module,
                comment: "Accessibility label of the fold")
            : String(
                localized: "Hide Quoted Text", table: "Compose", bundle: .module,
                comment: "Accessibility label of the open fold")
    }

    private func fieldChanged() {
        viewModel.subject = subjectField.text ?? ""
        updateSendEnabled()
    }

    private func show(_ body: MessageBody) {
        bodyView.attributedText = RichText(body).attributedString(font: bodyFont)
        bodyView.typingAttributes = RichText.plainAttributes(font: bodyFont)
    }

    /// Called after every change: Send follows whether it can go, and autosave keeps the draft a moment later.
    func updateSendEnabled() {
        sendItem.isEnabled = viewModel.canSend
        viewModel.edited { [weak self] in self?.body }
    }

    var body: MessageBody {
        RichText(bodyView.attributedText ?? NSAttributedString()).messageBody
    }

    /// Adds a picked file, or explains why it can't go.
    func add(_ attachment: DraftAttachment) {
        guard viewModel.attach(attachment) else { return tooLarge() }
        attachmentsView.show(viewModel.attachments)
        updateSendEnabled()
    }

    func send(at time: SendTime = .now) {
        fieldChanged()
        viewModel.send(body: body, at: time)
        close()
    }

    /// The times on offer now, then a picker for any other.
    private func sendLaterItems() -> [UIMenuElement] {
        let choices = LaterTime.sendChoices(at: .now).map { choice in
            UIAction(title: choice.title, image: UIImage(systemName: choice.symbol)) { [weak self] _ in
                self?.send(at: .at(choice.date))
            }
        }
        let pick = UIAction(
            title: String(
                localized: "Choose a Time…", table: "Compose", bundle: .module,
                comment: "Picks a later time from a calendar"),
            image: UIImage(systemName: "calendar")
        ) { [weak self] _ in self?.pickSendTime() }
        return [
            UIMenu(
                title: String(
                    localized: "Send Later", table: "Compose", bundle: .module,
                    comment: "Menu of times to send a message"),
                options: .displayInline, children: choices + [pick])
        ]
    }

    private func pickSendTime() {
        LaterPickerViewController.present(
            from: self,
            title: String(
                localized: "Send Later", table: "Compose", bundle: .module, comment: "Menu of times to send a message"),
            actionTitle: String(
                localized: "Schedule", table: "Compose", bundle: .module,
                comment: "Schedules the message for the picked time"),
            initial: LaterTime.sendChoices(at: .now).first?.date
        ) { [weak self] date in self?.send(at: .at(date)) }
    }

    private func cancel() {
        fieldChanged()
        guard viewModel.hasChanges(body: body) else {
            viewModel.closeUnchanged()
            return close()
        }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(
            UIAlertAction(
                title: String(
                    localized: "Delete Draft", table: "Compose", bundle: .module, comment: "Discards the message"),
                style: .destructive
            ) { [weak self] _ in self?.deleteDraft() })
        if viewModel.canSaveDraft {
            sheet.addAction(
                UIAlertAction(
                    title: String(
                        localized: "Save Draft", table: "Compose", bundle: .module,
                        comment: "Keeps the message in Drafts"),
                    style: .default
                ) { [weak self] _ in self?.saveDraft() })
        }
        sheet.addAction(
            UIAlertAction(
                title: String(
                    localized: "Keep Editing", table: "Compose", bundle: .module, comment: "Returns to the message"),
                style: .cancel))
        sheet.popoverPresentationController?.sourceItem = navigationItem.leftBarButtonItem
        present(sheet, animated: true)
    }

    /// Throws the message away and closes.
    func deleteDraft() {
        viewModel.deleteDraft()
        close()
    }

    /// Keeps the message in the provider's Drafts and closes.
    func saveDraft() {
        // Saving reads the editor, which a message restored to the pill hasn't loaded yet: blank fields would save over
        // what it says.
        loadViewIfNeeded()
        fieldChanged()
        viewModel.saveDraft(body: body)
        close()
    }

    /// The host took the message back after its send or save failed: writing goes on, kept as it is written.
    public func resumeAfterFailure() {
        viewModel.resumeKeeping()
    }

    /// The writer dismissed the message where it can't be minimized, as by dragging a share sheet down: one with
    /// something in it is saved to Drafts, one without closes, kept nowhere.
    public func dismissKeepingDraft() {
        fieldChanged()
        guard viewModel.canSaveDraft, viewModel.hasChanges(body: body) else {
            viewModel.closeUnchanged()
            return close()
        }
        saveDraft()
    }

    /// Takes the message off this window, as written so far, for a window of its own to go on with it. Nothing is
    /// sent, kept or deleted: the same message carries on there.
    func handOff() -> Draft {
        fieldChanged()
        let draft = written
        close()
        return draft
    }

    /// The message is done with: sent, deleted, saved away or closed unchanged. The host takes it off the screen.
    private func close() {
        picker.finish()
        host?.composerDidClose(self)
    }

    /// The draft as written so far, for the drafts shelf and the picker; as it opened before the editor loads.
    public var written: Draft { isViewLoaded ? viewModel.finished(body: body) : viewModel.draft }

    /// How a message dragged down leaves: one with something in it is minimized, one without is discarded.
    enum Leaving {
        case minimize
        case discard
    }

    /// A drag down on the card began, taking the message off the screen unless it is let go short.
    func startLeaving() -> Leaving {
        fieldChanged()
        let leaving: Leaving = viewModel.hasChanges(body: body) ? .minimize : .discard
        prepareToLeave(keeping: leaving == .minimize)
        return leaving
    }

    /// The drag was let go short: writing goes on where it was.
    func stayed() {
        guard case .leaving(let field) = showing else { return }
        showing = .shown
        field?.becomeFirstResponder()
    }

    /// The card reached the drafts pill, or left by its corner.
    func didMinimize() {
        guard case .leaving(let field) = showing else { return }
        showing = .minimized(field)
    }

    /// The card left with nothing written: the message closes, kept nowhere.
    func discard() {
        viewModel.closeUnchanged()
        close()
    }

    /// Moves the message out of the way into the drafts pill, kept as it is, to come back to.
    func minimize(then next: (() -> Void)? = nil) {
        prepareToLeave(keeping: true)
        if let host { host.minimize(self, then: next) } else { next?() }
    }

    private func prepareToLeave(keeping: Bool) {
        fieldChanged()
        if keeping { viewModel.keepNow(body: body) }
        // Read before editing ends, which leaves no field focused.
        showing = .leaving(lastFocused)
        view.endEditing(true)
    }

    /// Whether the message shows from its top, where a drag down takes the card down rather than scrolling.
    var isScrolledToTop: Bool {
        scrollView.contentOffset.y <= -scrollView.adjustedContentInset.top
    }

    /// The scrolling that waits for a drag down on the card to fail first.
    var scrollPan: UIGestureRecognizer { scrollView.panGestureRecognizer }

    /// The VoiceOver escape gesture minimizes the message, as the swipe down does.
    public override func accessibilityPerformEscape() -> Bool {
        guard host?.canMinimize == true else { return false }
        minimize()
        return true
    }
}

extension ComposeViewController: UITextViewDelegate {
    public func textViewDidBeginEditing(_ textView: UITextView) {
        lastFocused = textView
    }

    public func textViewDidChange(_ textView: UITextView) {
        updateSendEnabled()
        settleTypedLayout()
    }

    public func textView(
        _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
    ) -> Bool {
        if text == "\n",
            let command = FormattingCommand.onReturn(
                in: textView.textStorage, selection: range, typingAttributes: textView.typingAttributes)
        {
            applyFormatting(command)
            return false
        }
        prepareTypedLayout(replacing: range, with: text)
        return true
    }

    public func textViewDidChangeSelection(_ textView: UITextView) {
        repairTypingLayout()
        showFormatting()
    }
}
