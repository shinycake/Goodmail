import MailCore
public import QuickLook
public import UIKit

/// A conversation read as letters: the subject, a slim timeline of earlier messages, and cards for the ones that
/// matter now. Renders `ThreadViewModel` through Observation (ADR-011).
public final class ThreadViewController: UIViewController {
    let viewModel: ThreadViewModel
    private let openURL: (URL) -> Void
    private let starItem = UIBarButtonItem()
    /// Reply, or Edit Draft while the newest message is an unsent draft.
    private var replyItem = UIBarButtonItem()
    private lazy var editDraftItem = makeEditDraftItem()
    let scrollView = UIScrollView()
    let stack = UIStackView()
    private let subject = UILabel()
    private let metadata = UILabel()
    private var cards: [Message.ID: MessageCardView] = [:]
    /// The classic layout's letters for my replies on their way.
    private var pendingLetters: [Draft.ID: PendingLetterView] = [:]
    /// Where the chat's field began when the undo toast was last placed above it.
    private var placedFloorTop: CGFloat?
    /// How much the undo toast covers above the chat's field, which the chat's end scrolls clear of.
    private var toastHeight: CGFloat = 0
    private var rows: [Message.ID: TimelineRowView] = [:]
    /// Chat runs by their first bubble, which stays first as later messages join the run.
    private var runs: [ChatTranscript.Bubble.ID: ChatRunView] = [:]
    private var timestamps: [Date: ChatTimestampView] = [:]
    /// My replies on their way that the chat has shown, so a new one scrolls the chat to it once.
    private var shownReplies: Set<Draft.ID> = []
    /// The classic letter just sent and where scrolling to it left the view, until its body takes its height.
    private var followedLetter: FollowedLetter?
    let layoutItem = UIBarButtonItem()
    /// The window's toolbar over the letter on a desktop window, as last laid out; `nil` where the bar at the bottom
    /// holds the controls.
    var windowToolbar: WindowToolbar?
    /// The chat's message field and folded mail actions, in place of the toolbar while the chat layout shows.
    private let composer = ChatComposerBar()
    /// Letters keep a readable width; chat bubbles reach nearly to the edges.
    private var readableWidth: [NSLayoutConstraint] = []
    private var chatWidth: [NSLayoutConstraint] = []
    private var observation: Task<Void, Never>?
    /// The layout the reader last scrolled to the focused message in; switching layouts scrolls there again.
    private var focusedLayout: ConversationLayout?
    private var previewURL: URL?
    /// The way off the mailing list the conversation came from, shown under the subject while it applies.
    private let unsubscribeOffer: UnsubscribeOffer?
    private lazy var unsubscribeBanner = UnsubscribeBanner()
    /// The reader's request to leave the list, cancelled if the reader leaves first.
    private var unsubscribing: Task<Void, Never>?
    /// The glass pill that shows a hovered link's address, and the find bar under the top bar (desktop windows).
    let readerPill = ReaderPill()
    let findBar = ConversationFindBar()
    let find = ConversationFind()
    let downloads = DownloadsSaver()
    /// The Share menu: the conversation as files to share, or printed.
    lazy var exporter = ConversationExporter(presenter: self)
    lazy var shareItem = exporter.shareItem(
        anchor: { [weak self] in self?.exportAnchor }, conversation: { [weak self] in self?.exportedConversation })
    /// Where the share sheet and the print panel point from: Share, or More on a desktop window, whose toolbar holds
    /// Share in that menu and so has no Share button to point from.
    var exportAnchor: UIBarButtonItem { windowToolbar?.more ?? shareItem }

    public init(
        viewModel: ThreadViewModel, openURL: @escaping (URL) -> Void, unsubscribeOffer: UnsubscribeOffer? = nil
    ) {
        self.viewModel = viewModel
        self.openURL = openURL
        self.unsubscribeOffer = unsubscribeOffer
        super.init(nibName: nil, bundle: nil)
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    deinit {
        observation?.cancel()
        unsubscribing?.cancel()
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.accessibilityIdentifier = "thread"
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        subject.font = Typography.system(.title1, weight: .bold)
        subject.adjustsFontForContentSizeCategory = true
        subject.numberOfLines = 0
        subject.accessibilityTraits = .header
        subject.accessibilityIdentifier = "thread.subject"
        metadata.font = .preferredFont(forTextStyle: .subheadline)
        metadata.textColor = .secondaryLabel
        metadata.adjustsFontForContentSizeCategory = true
        metadata.numberOfLines = 0
        let header = UIStackView(arrangedSubviews: [subject, metadata])
        header.axis = .vertical
        header.spacing = 6
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 8, leading: 4, bottom: 8, trailing: 4)
        header.isLayoutMarginsRelativeArrangement = true

        stack.axis = .vertical
        stack.spacing = 12
        stack.addArrangedSubview(header)
        configureToolbar()
        layoutItem.primaryAction = UIAction { [weak self] _ in self?.viewModel.switchLayout() }
        placeShareItem()
        registerForTraitChanges([UITraitHorizontalSizeClass.self, InteractionStyleTrait.self]) { (self: Self, _) in
            self.placeShareItem()
        }
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let readable = scrollView.readableContentGuide
        readableWidth = [
            stack.leadingAnchor.constraint(equalTo: readable.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: readable.trailingAnchor),
        ]
        let frame = scrollView.frameLayoutGuide
        chatWidth = [
            stack.leadingAnchor.constraint(equalTo: frame.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: frame.trailingAnchor, constant: -12),
        ]
        configureComposer()
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
        ])

        installReaderOverlays()
        subject.setSubjectText(displaySubject)
        observation = Task { [viewModel] in await viewModel.observe() }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        showToolbar(animated: animated)
        wear(.account(viewModel.accountColor))
    }

    /// Again once on screen, for a swipe back that was let go of before the list took over: the list set its toolbar
    /// as it started to appear.
    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        showToolbar(animated: animated)
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if isMovingFromParent || isBeingDismissed { composer.finish() }
    }

    /// Letters keep the toolbar; the chat's composer takes its place. The toolbar belongs to the stack, and each
    /// screen sets it as it appears, so the reader touches it only while it is the one on top: once it is going back
    /// to the list, the list has set its own, and a change to the thread then must not hide the list's Search,
    /// New Message and selection actions.
    private func showToolbar(animated: Bool) {
        guard let navigationController, navigationController.topViewController === self else { return }
        navigationController.setToolbarHidden(viewModel.layout == .chat || usesWindowToolbar, animated: animated)
    }

    /// Keeps the conversation's end clear of the composer, which rides on top of the keyboard.
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The undo toast sits above the chat's field, which rides on the keyboard.
        let floorTop = composer.isHidden ? nil : composer.frame.minY
        if floorTop != placedFloorTop {
            placedFloorTop = floorTop
            toastFloorChanged()
        }
        let covered =
            composer.isHidden
            ? 0 : max(0, view.bounds.height - view.safeAreaInsets.bottom - composer.frame.minY) + toastHeight
        guard scrollView.contentInset.bottom != covered else { return }
        let atEnd =
            scrollView.contentOffset.y + scrollView.bounds.height
            >= scrollView.contentSize.height + scrollView.adjustedContentInset.bottom - 24
        scrollView.contentInset.bottom = covered
        scrollView.verticalScrollIndicatorInsets.bottom = covered
        if atEnd { scrollToEnd() }
    }

    private func scrollToEnd(animated: Bool = false) {
        let inset = scrollView.adjustedContentInset
        let end = max(-inset.top, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        scrollView.setContentOffset(CGPoint(x: 0, y: end), animated: animated)
    }

    private func configureComposer() {
        composer.presenter = self
        composer.setAccentColor(viewModel.accountColor.uiColor)
        composer.onSend = { [weak self] text, attachments, time in
            self?.viewModel.sendChatReply(text, attachments: attachments, at: time)
        }
        composer.onExpand = { [weak self] text, attachments in
            self?.viewModel.expandChatReply(text, attachments: attachments)
        }
        composer.onResize = { [weak self] in self?.view.setNeedsLayout() }
        // What is dropped on a chat goes into its reply, as in Messages; a letter leaves it to a new message.
        view.addInteraction(composer.intake.makeInteraction())
        composer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(composer)
        // A bar's region along the bottom keeps the field and its buttons clear of the corner a window on iPad is
        // resized by, as the system's toolbars are. It takes the extent of a standard toolbar: the form without one
        // is missing from the UIKit that macOS 27.2 ships for iOS apps and Mac Catalyst, so an app that used it
        // wouldn't launch on a Mac.
        let bar = view.layoutGuide(for: .bar(onEdge: UIRectEdge.bottom, extent: 44))
        NSLayoutConstraint.activate([
            composer.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            composer.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            composer.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
        ])
    }

    /// The chat reads under the subject in the bar with its people below it, and the composer takes the
    /// toolbar's place; letters keep the large subject header and the toolbar.
    private func applyLayout(_ layout: ConversationLayout) {
        let chat = layout == .chat
        // The chat's bubbles aren't letters the find bar searches.
        if chat { find.close() }
        NSLayoutConstraint.deactivate(chat ? readableWidth : chatWidth)
        NSLayoutConstraint.activate(chat ? chatWidth : readableWidth)
        stack.arrangedSubviews.first?.isHidden = chat
        composer.isHidden = !chat
        if viewIfLoaded?.window != nil { showToolbar(animated: true) }
        let subject = displaySubject
        navigationItem.title = chat ? subject : nil
        navigationItem.subtitle = chat ? participantsText : nil
        if chat { composer.setActions(toolbarItems?.filter { $0.image != nil } ?? []) }
    }

    /// "Dana Levi", or "Dana, Avi and Yael": everyone else on the conversation, by first name when there are
    /// several.
    private var participantsText: String? {
        let others = viewModel.transcript.others
        guard !others.isEmpty else { return nil }
        let names = others.map { contact in
            others.count > 1
                ? contact.displayName.split(separator: " ").first.map(String.init) ?? "" : contact.displayName
        }
        return names.formatted(.list(type: .and, width: .narrow))
    }

    private func answerAction(_ answer: Answer) -> UIAction {
        UIAction(title: answer.title, image: UIImage(systemName: answer.symbol)) { [weak self] _ in
            self?.viewModel.answer(answer)
        }
    }

    /// Archive, Trash, Snooze, Mute and Unread go through the window's actions, which tell the window to move the
    /// reader on.
    private func configureToolbar() {
        func item(_ action: ThreadAction) -> UIBarButtonItem {
            UIBarButtonItem(
                title: action.title, image: UIImage(systemName: action.symbol),
                primaryAction: UIAction { [weak self] _ in self?.viewModel.perform(action) })
        }
        starItem.primaryAction = UIAction { [weak self] _ in
            guard let self else { return }
            viewModel.perform(.star(!viewModel.isStarred))
        }
        replyItem = UIBarButtonItem(
            title: String(localized: "Reply", table: "Thread", bundle: .module, comment: "Composer title for a reply"),
            image: UIImage(systemName: "arrowshape.turn.up.left"),
            primaryAction: UIAction { [weak self] _ in self?.viewModel.answer(.reply) },
            // The alternatives only: a tap is Reply, and a toolbar that overflows into More lists the primary action
            // beside these, so a Reply here would show twice. Edit as New starts a message of its own, set apart.
            menu: UIMenu(children: [
                UIMenu(
                    options: .displayInline, children: [.replyAll, .forward, .forwardAsAttachment].map(answerAction)),
                UIMenu(options: .displayInline, children: [answerAction(.editAsNew)]),
            ]))
        // Answering is the last to go into More when the toolbar runs short, as in a bar down iPhone Duo's side.
        replyItem.visibilityPriority = .high
        editDraftItem.visibilityPriority = .high
        toolbarItems = [
            item(.archive), viewModel.isInTrash ? deleteForeverItem() : item(.trash),
            .snooze(from: self) { [weak self] in self?.viewModel.snooze(until: $0) }, .flexibleSpace(),
            item(.markRead(false)), starItem,
            .organize(
                move: { [weak self] in self?.viewModel.move() },
                changeLabels: { [weak self] in self?.viewModel.changeLabels() },
                pinning: { [weak self] in self?.viewModel.isPinned == false },
                pin: { [weak self] in self?.viewModel.pin($0) },
                mute: { [weak self] in self?.viewModel.muteAction },
                perform: { [weak self] in self?.viewModel.perform($0) }),
            .fixedSpace(0), replyItem,
        ]
    }

    /// Edit Draft, in Reply's place while the newest message is an unsent draft.
    func makeEditDraftItem() -> UIBarButtonItem {
        UIBarButtonItem(
            title: String(
                localized: "Edit Draft", table: "Thread", bundle: .module, comment: "Opens a saved draft to finish it"),
            image: UIImage(systemName: "square.and.pencil"),
            primaryAction: UIAction { [weak self] _ in self?.viewModel.editDraft() })
    }

    /// Delete Forever, which asks first, in Trash's place in Trash.
    func deleteForeverItem() -> UIBarButtonItem {
        UIBarButtonItem(
            title: ThreadAction.deleteForever.title, image: UIImage(systemName: ThreadAction.deleteForever.symbol),
            primaryAction: UIAction { [weak self] _ in
                let alert = UIAlertController.deleteForever(.threads(1)) { [weak self] in
                    self?.viewModel.perform(.deleteForever)
                }
                self?.present(alert, animated: true)
            })
    }

    /// Share sits beside the layout switch in a regular-width window, where the toolbar has no More menu to take
    /// what doesn't fit and dropped it, and in the toolbar on a phone, where More holds it when the bar runs short.
    private func placeShareItem() {
        if usesWindowToolbar { return placeWindowToolbar() }
        let regular = traitCollection.horizontalSizeClass == .regular
        navigationItem.rightBarButtonItems = regular ? [layoutItem, shareItem] : [layoutItem]
        var items = (toolbarItems ?? []).filter { $0 !== shareItem }
        if !regular, let reply = items.indices.last { items.insert(shareItem, at: reply - 1) }
        toolbarItems = items
    }

    public override func updateProperties() {
        super.updateProperties()
        let star: ThreadAction = .star(!viewModel.isStarred)
        starItem.image = UIImage(systemName: viewModel.isStarred ? "star.fill" : "star")
        // The title, not just an accessibility label: when the toolbar overflows into More, the menu shows it.
        starItem.title = star.title
        let answer = viewModel.draft == nil ? replyItem : editDraftItem
        if var items = toolbarItems, let last = items.indices.last, items[last] !== answer {
            items[last] = answer
            toolbarItems = items
        }
        updateWindowToolbar()
        let messages = viewModel.messages
        metadata.text = [viewModel.accountEmail, Self.countText(messages.count)]
            .filter { !$0.isEmpty }.joined(separator: " · ")

        let other = viewModel.layout.other
        layoutItem.image = UIImage(systemName: other == .chat ? "bubble.left.and.bubble.right" : "doc.plaintext")
        layoutItem.title = other.showTitle
        stack.spacing = viewModel.layout == .chat ? 10 : 12
        applyLayout(viewModel.layout)

        let header = stack.arrangedSubviews[0]
        let arranged =
            [header] + unsubscribeViews(messages)
            + (viewModel.layout == .chat
                ? chatViews(viewModel.transcript) : letterViews(messages) + replyViews(viewModel.replies))
        if arranged != stack.arrangedSubviews {
            for view in stack.arrangedSubviews { view.removeFromSuperview() }
            arranged.forEach(stack.addArrangedSubview)
        }
        scrollToFocusOnce()
        followNewReplies()
    }

    /// A reply just sent rises at the end of the conversation, in either layout, so it scrolls down to it.
    private func followNewReplies() {
        let replies = Set(viewModel.replies.map(\.id))
        defer { shownReplies = replies }
        let new = replies.subtracting(shownReplies)
        guard !new.isEmpty else { return }
        view.layoutIfNeeded()
        let animated = !SystemAccessibility.reducesMotion
        switch viewModel.layout {
        case .chat:
            scrollToEnd(animated: animated)
        case .classic:
            // A letter is taller than the screen's end, and its body lays out after, so its top is what shows.
            guard let reply = viewModel.replies.last(where: { new.contains($0.id) }),
                let letter = pendingLetters[reply.id]
            else { return }
            followedLetter = FollowedLetter(reply: reply.id, offset: scrollToTop(of: letter, animated: animated))
        }
    }

    /// The followed letter's body grew under its header, so its top shows again, unless the reader scrolled away.
    private func letterLaidOut(_ reply: Draft.ID) {
        guard let followed = followedLetter, followed.reply == reply else { return }
        followedLetter = nil
        guard let letter = pendingLetters[reply], abs(scrollView.contentOffset.y - followed.offset.y) < 1 else {
            return
        }
        view.layoutIfNeeded()
        scrollToTop(of: letter, animated: !SystemAccessibility.reducesMotion)
    }

    /// The banner offering to leave the conversation's mailing list, when it came from one.
    private func unsubscribeViews(_ messages: [Message]) -> [UIView] {
        guard let unsubscribeOffer, let offer = unsubscribeOffer.offer(in: messages) else { return [] }
        unsubscribeBanner.configure(offer, tint: viewModel.accountColor.uiColor)
        unsubscribeBanner.onAction =
            switch offer.state {
            case .pageOpened: { unsubscribeOffer.finished(offer) }
            case .offered, .failed, .unsubscribing, .unsubscribed: { [weak self] in self?.confirmUnsubscribe(offer) }
            }
        return [unsubscribeBanner]
    }

    private func confirmUnsubscribe(_ offer: UnsubscribeOffer.Offer) {
        let alert = UIAlertController.unsubscribe(offer, accountEmail: viewModel.accountEmail) { [weak self] in
            guard let self, let unsubscribeOffer, unsubscribing == nil else { return }
            unsubscribing = Task { [weak self] in
                await unsubscribeOffer.unsubscribe(offer)
                self?.unsubscribing = nil
            }
        }
        present(alert, animated: true)
    }

    /// What VoiceOver lands on as this reader takes another's place: the subject, or the screen itself where the
    /// chat shows the subject in the bar instead.
    public var spokenLanding: Any {
        viewModel.layout == .chat ? view as Any : subject
    }

    /// The subject as the reader shows it, with a placeholder for none.
    private var displaySubject: String {
        viewModel.thread.subject.isEmpty ? ThreadRowMetrics.noSubject : viewModel.thread.subject
    }

    /// The conversation as it is now, for Share and Print. Each message keeps the appearance it shows in: its card's,
    /// or the app's for one without a card and in the chat layout, whose bubbles follow the app.
    var exportedConversation: ConversationExporter.Conversation {
        let shown: [Message.ID: UIUserInterfaceStyle] =
            switch viewModel.layout {
            case .classic: cards.mapValues(\.shownStyle)
            case .chat: [:]
            }
        let app: UIUserInterfaceStyle = traitCollection.userInterfaceStyle == .dark ? .dark : .light
        return ConversationExporter.Conversation(
            subject: displaySubject,
            messages: viewModel.messages, appearance: { shown[$0] ?? app },
            allowsRemoteContent: viewModel.remoteContentAllowed,
            attachmentData: viewModel.attachmentData, source: viewModel.source)
    }

    /// Cards for the open messages and one-line rows for the rest.
    private func letterViews(_ messages: [Message]) -> [UIView] {
        var arranged: [UIView] = []
        for message in messages {
            let dateText = viewModel.dateText(for: message)
            if viewModel.expanded.contains(message.id) {
                let card = cards[message.id] ?? makeCard(for: message.id)
                card.configure(
                    message, dateText: dateText, accountEmail: viewModel.accountEmail,
                    accountColor: viewModel.accountColor.uiColor,
                    allowsRemoteContent: viewModel.allowsRemoteContent(in: message))
                arranged.append(card)
            } else {
                let row = rows[message.id] ?? makeRow(for: message.id)
                row.configure(message, dateText: dateText)
                arranged.append(row)
            }
        }
        return arranged
    }

    /// My replies on their way, after the messages, as the letters they will be once their copies sync.
    private func replyViews(_ replies: [PendingReply]) -> [UIView] {
        var shown: [Draft.ID: PendingLetterView] = [:]
        defer { pendingLetters = shown }
        return replies.map { reply in
            let view = pendingLetters[reply.id] ?? makePendingLetter(for: reply)
            shown[reply.id] = view
            view.configure(
                reply, dateText: viewModel.dateText(for: reply.letter), accountEmail: viewModel.accountEmail,
                accountColor: viewModel.accountColor.uiColor, actions: deliveryActions)
            return view
        }
    }

    private func makePendingLetter(for reply: PendingReply) -> PendingLetterView {
        let id = reply.letterID
        let view = PendingLetterView(attachmentData: viewModel.attachmentData)
        view.card.openURL = openURL
        wireDesktop(view.card, message: id)
        view.card.onBodyLayout = { [weak self, replyID = reply.id] in self?.letterLaidOut(replyID) }
        view.card.onOpenAttachment = { [weak self, weak view] attachment in
            self?.open(attachment, in: id) { view?.card.setLoading($0, for: attachment) }
        }
        return view
    }

    /// What the caption under a reply on its way does, in either layout.
    private var deliveryActions: ChatDeliveryView.Actions {
        ChatDeliveryView.Actions(
            retry: { [weak self] in self?.viewModel.retry($0) },
            edit: { [weak self] in self?.viewModel.edit($0) },
            discard: { [weak self] in self?.viewModel.discard($0) },
            moveToDrafts: { [weak self] in self?.viewModel.moveToDrafts($0) })
    }

    /// Timestamps and runs of bubbles, reusing the views already made for them.
    private func chatViews(_ transcript: ChatTranscript) -> [UIView] {
        let actions = ChatBubbleActions(
            openLetter: { [weak self] in self?.openLetter($0) },
            openAttachment: { [weak self] attachment, message, loading in
                self?.open(attachment, in: message, loading: loading)
            },
            showQuoted: { [weak self] in self?.scroll(to: $0, animated: true) },
            openURL: openURL,
            pending: deliveryActions)
        let times = Dictionary(
            viewModel.messages.map { ($0.id, viewModel.timestampText(for: $0.date)) },
            uniquingKeysWith: { first, _ in first })
        // Only the entries shown now keep their views, so a message that left the thread lets its views go.
        var shownRuns: [ChatTranscript.Bubble.ID: ChatRunView] = [:]
        var shownTimestamps: [Date: ChatTimestampView] = [:]
        defer { (runs, timestamps) = (shownRuns, shownTimestamps) }
        return transcript.entries.compactMap { entry -> UIView? in
            switch entry {
            case .timestamp(let date):
                let label = timestamps[date] ?? ChatTimestampView()
                shownTimestamps[date] = label
                label.text = viewModel.timestampText(for: date)
                return label
            case .run(let run):
                guard let first = run.bubbles.first else { return nil }
                let view = runs[first.id] ?? ChatRunView()
                shownRuns[first.id] = view
                view.configure(
                    run, isGroup: transcript.isGroup, accountColor: viewModel.accountColor.uiColor,
                    actions: actions, timeText: { times[$0] ?? "" })
                return view
            }
        }
    }

    /// A long or laid-out message, in full over the chat.
    private func openLetter(_ message: Message.ID) {
        let sheet = LetterSheetController(
            viewModel: viewModel, message: message, openURL: openURL,
            openAttachment: { [weak self] attachment, loading in self?.open(attachment, in: message, loading: loading) }
        )
        let navigation = UINavigationController(rootViewController: sheet)
        navigation.sheetPresentationController?.detents = [.large()]
        navigation.sheetPresentationController?.prefersGrabberVisible = true
        present(navigation, animated: true)
    }

    private func makeCard(for id: Message.ID) -> MessageCardView {
        let card = MessageCardView(attachmentData: viewModel.attachmentData)
        card.onToggle = { [weak self] in self?.viewModel.toggle(id) }
        card.onAllowRemoteContent = { [weak self] in self?.viewModel.allowRemoteContent(in: id) }
        card.onTrust = { [weak self] in self?.viewModel.alwaysAllowRemoteContent(by: $0) }
        card.openURL = openURL
        wireDesktop(card, message: id)
        card.onOpenAttachment = { [weak self, weak card] attachment in
            self?.open(attachment, in: id) { card?.setLoading($0, for: attachment) }
        }
        cards[id] = card
        return card
    }

    private func makeRow(for id: Message.ID) -> TimelineRowView {
        let row = TimelineRowView()
        row.addAction(UIAction { [weak self] _ in self?.viewModel.toggle(id) }, for: .primaryActionTriggered)
        rows[id] = row
        return row
    }

    /// Downloads the file, with `loading` showing it on whatever the reader tapped, then previews it from the
    /// controller in front, which may be a letter's sheet.
    private func open(_ attachment: Attachment, in message: Message.ID, loading: @escaping (Bool) -> Void) {
        loading(true)
        Task {
            defer { loading(false) }
            do {
                previewURL = try await viewModel.file(for: attachment, in: message)
                let preview = QLPreviewController()
                preview.dataSource = self
                (presentedViewController ?? self).present(preview, animated: true)
            } catch {
                let alert = UIAlertController(
                    title: String(
                        localized: "Couldn’t Open Attachment", table: "Thread", bundle: .module,
                        comment: "Alert title when an attachment fails to download"),
                    message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(
                    UIAlertAction(
                        title: String(localized: "OK", table: "Thread", bundle: .module, comment: "Dismiss"),
                        style: .default))
                (presentedViewController ?? self).present(alert, animated: true)
            }
        }
    }

    /// Opens on the first unread message, or the newest, once the messages first arrive in each layout.
    private func scrollToFocusOnce() {
        guard focusedLayout != viewModel.layout, let focus = viewModel.firstFocused, viewModel.messages.count > 1,
            scroll(to: focus, animated: false)
        else { return }
        focusedLayout = viewModel.layout
    }

    /// Scrolls the message's card or bubble to the top, or as far as the content goes. False when it isn't shown.
    @discardableResult
    private func scroll(to message: Message.ID, animated: Bool) -> Bool {
        let shown: UIView? =
            switch viewModel.layout {
            case .classic: cards[message] ?? rows[message]
            case .chat: runs.values.lazy.compactMap { $0.view(for: message) }.first
            }
        guard let shown, shown.isDescendant(of: scrollView) else { return false }
        view.layoutIfNeeded()
        scrollToTop(of: shown, animated: animated)
        return true
    }

    /// Scrolls `shown`'s top to just under the bar, or as near as the content's end allows, and returns that offset.
    @discardableResult
    private func scrollToTop(of shown: UIView, animated: Bool) -> CGPoint {
        let inset = scrollView.adjustedContentInset
        let target = shown.convert(shown.bounds, to: scrollView).minY - inset.top - 8
        let bottom = max(-inset.top, scrollView.contentSize.height + inset.bottom - scrollView.bounds.height)
        let offset = CGPoint(x: 0, y: min(bottom, max(-inset.top, target)))
        scrollView.setContentOffset(offset, animated: animated)
        return offset
    }

    static func countText(_ count: Int) -> String {
        guard count > 1 else { return "" }
        return String(
            localized: "\(count) messages", table: "Thread", bundle: .module,
            comment: "How many messages a thread holds")
    }
}

extension ThreadViewController: QLPreviewControllerDataSource {
    public func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
        previewURL == nil ? 0 : 1
    }

    public func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
        (previewURL ?? URL(filePath: "/")) as NSURL
    }
}

extension ThreadViewController: UndoToastFloor {
    var toastFloor: UIView? { composer.isHidden ? nil : composer }

    func toastCovers(_ height: CGFloat) {
        guard height != toastHeight else { return }
        toastHeight = height
        viewIfLoaded?.setNeedsLayout()
    }
}

/// A letter just sent that the classic layout scrolled to, and the offset that scroll left.
private struct FollowedLetter {
    let reply: Draft.ID
    let offset: CGPoint
}
