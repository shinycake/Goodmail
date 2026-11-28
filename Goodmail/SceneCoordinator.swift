import IMAPProvider
import MailCore
import MailStore
import MailUI
import OSLog
import UIKit
import UserNotifications

#if canImport(MailIntents)
    import MailIntents
#endif

/// One per window (ADR-011): decides what the window shows and owns the flows that change it.
final class SceneCoordinator: NSObject {
    /// The window this coordinator fills, which undoes the last mail action when shaken.
    let window: ShakeToUndoWindow
    let model: AppModel
    /// The window's actions, whose last one its undo toast offers to take back.
    let actions: MailActions
    /// New Viewer Window, New Message and Get Mail, with the sync Get Mail starts here.
    let everyWindow: EveryWindowCommands
    /// Signing an account in again.
    private var signingInAgain: Task<Void, Never>?
    /// An answer or a draft to finish, waiting for the message it starts from, which a newer one replaces.
    var answering: Task<Void, Never>?
    /// Follows the labels and smart mailboxes here, so a list gone from the device gives way (`followOwnLists`).
    var listsCheck: Task<Void, Never>?
    /// The label or move picker's threads and labels, read off the main actor before it opens; a newer one replaces it.
    var pickingLabels: Task<Void, Never>?
    /// What fills the window. After `init`, only `enter(_:)` changes it.
    private(set) var screen: Screen
    /// Follow each pass that brings this device's accounts and settings in step with the reader's other devices.
    var deviceObservers: [any NSObjectProtocol] = []
    /// The screen receiving accounts from another device, so a code the Camera app opens while it's up goes to it.
    var receivingTransfer: ReceivingTransfer?
    /// The window's root, which holds the mail screens and the messages minimized below them.
    let drafts = DraftShelfViewController()
    /// Names this window's minimized messages in the database. Fresh each launch, so the next one finds them unclaimed.
    private let windowID = DraftWindowTicket(window: UUID().uuidString)
    /// What the window shows and the one place it moves (`SceneCoordinator+Navigation`), which keeps the viewer's
    /// screens showing it. What it shows is saved for the system to restore the window or hand it off (`activity`).
    let navigator: WindowNavigator
    var shown: WindowState { navigator.state }

    /// The mailboxes' model on show, which the lists ask for the rows ⌘1 to ⌘9 reach; `nil` without the mail screens.
    var sidebar: MailboxesViewModel? { navigator.screens?.mailboxes }
    /// Opens the smart mailbox editor and stores what it saves (ADR-039).
    private(set) lazy var smartMailboxFlow = SmartMailboxFlow(
        store: model.smartMailboxStore(), presenter: { [weak self] in self?.topViewController() })

    /// The thread the window is reading, for Get Open Conversation.
    var openThread: ThreadSummary.ID? { shown.reading?.thread }

    /// `restoring` is what the window showed when the system last saved it, or what another device handed off.
    /// `lists` says when a list it names, missing here, counts as gone. `filled` is called once, as the window first
    /// fills with a screen, which the scene waits for to hand on an arrival held for it (`SceneDelegate`).
    init(
        windowScene: UIWindowScene, model: AppModel, restoring: WindowState?, lists: WindowState.ListCheck,
        filled: @escaping (SceneCoordinator) -> Void
    ) {
        self.model = model
        screen = .starting(filled: filled)
        let actions = MailActions(commands: model.commands)
        self.actions = actions
        everyWindow = EveryWindowCommands(model: model)
        let window = ShakeToUndoWindow(windowScene: windowScene, undo: { actions.undoLast() })
        self.window = window
        // Edit > Undo and ⌘Z take back the window's last action, as a shake does.
        actions.undoManager = window.undoManager
        window.traitOverrides.senderPictures = model.senderPictures
        navigator = WindowNavigator(
            showing: window.interactionStyle.laying(out: restoring?.keeping(model.accounts.map(\.id)) ?? WindowState()),
            checking: lists,
            context: { [weak window, model] in
                WindowNavigation.Context(
                    arrangement: WindowNavigation.Arrangement(window?.windowScene?.traitCollection ?? .current),
                    afterRemoval: Preferences.afterRemoval, unsortedInboxes: model.unsortedInboxAccounts)
            },
            lookUp: { [lookup = model.conversationLookup] in await lookup.find($0) },
            stored: { [database = model.database] id in
                do {
                    return try await database.offMain { try $0.thread(id) }
                } catch {
                    Logger.windows.error("Couldn't read a thread to show: \(error, privacy: .private)")
                    return nil
                }
            })
        super.init()
        window.windowAnswer = { [weak self] in self?.windowAnswer(to: $0) ?? .notHere }
        actions.reopen = { [weak self] draft in self?.handle(.compose(draft)) }
        drafts.newMessage = { [weak self] account in self?.handle(.compose(Draft(accountID: account))) }
        drafts.newMessageHolding = { [weak self] in self?.compose(holding: $0) }
        drafts.canStartMessage = { [weak self] in self?.composingAccount != nil }
        drafts.keep = { [minimized = model.minimizedDrafts, ticket = windowID] in minimized.keep($0, for: ticket) }
        followNavigation()
    }

    isolated deinit {
        for observer in deviceObservers { NotificationCenter.default.removeObserver(observer) }
        signingInAgain?.cancel()
        answering?.cancel()
        listsCheck?.cancel()
        pickingLabels?.cancel()
        if case .leaving(let waiting) = screen { waiting.cancel() }
    }

    /// The window is going away; another window may take its minimized messages.
    func close() {
        model.minimizedDrafts.close(windowID)
    }

    func start() {
        // The window shows its root at once, empty until the first screen fills it, as the mail screens wait for the
        // conversation read to be read off the main actor (`showMailbox`).
        window.rootViewController = drafts
        observeSharedAccounts()
        observeSyncedSettings()
        followOwnLists()
        if model.accounts.isEmpty {
            // A new device whose reader has accounts on another one, or a reinstall, offers those first.
            if model.accountOffer == nil { showWelcome() } else { offerSharedAccounts() }
        } else {
            showMailbox()
            claimMinimizedDrafts()
        }
    }

    /// Offers a failed send: edit it, try it again, or delete it. `false` when another alert is up, so it waits.
    /// Which failed sends to offer, once a launch, is the app's (`LaunchAlerts`).
    func offerFailure(of message: OutgoingMessage) -> Bool {
        guard let presenter = topViewController(), !(presenter is UIAlertController) else { return false }
        let actions = actions
        let alert = SendFailureAlert.make(
            for: message,
            edit: { actions.discardSend(message, edit: true) },
            retry: { actions.retrySend(message) },
            delete: { actions.discardSend(message) })
        presenter.present(alert, animated: true)
        return true
    }

    /// Asks `account`, a Gmail account whose sign-in can't delete forever, to sign in again, unless another alert is
    /// up. The app asks once a launch (`LaunchAlerts`).
    func askToSignInAgain(_ account: Account) {
        guard let presenter = topViewController(), !(presenter is UIAlertController) else { return }
        let alert = UIAlertController.signInAgainToDeleteForever(account.email) { [weak self] in
            self?.signInAgain(account.id)
        }
        presenter.present(alert, animated: true)
    }

    /// Signs `id` in again, its new sign-in replacing the old one and keeping the account. Replaces a sign-in already
    /// under way.
    func signInAgain(_ id: AccountID) {
        guard let account = model.accounts.first(where: { $0.id == id }) else { return }
        signingInAgain?.cancel()
        signingInAgain = Task { [accountSignIn] in await accountSignIn.signIn(againTo: account) }
    }

    /// Brings the messages minimized in windows that are gone back to the drafts pill, with what was dropped for a
    /// message whose own window went away before reading it back, which goes in once its composer opens. Where every
    /// message has a window there is no pill: a window's message is read back by that window when the system restores
    /// it, and autosave has it in Drafts.
    private func claimMinimizedDrafts() {
        switch window.interactionStyle.composePlacement {
        case .sheet:
            model.minimizedDrafts.claim(for: windowID) { [weak self] minimized, dropped in
                guard let self else { return }
                drafts.restore(
                    minimized.compactMap { draft in
                        let composer = composer(for: draft)
                        if let composer, let loaded = dropped[ComposeWindow(for: draft.id).key] {
                            composer.whenOpen { [weak composer] in composer?.receive(loaded) }
                        }
                        return composer
                    })
            }
        case .ownWindow:
            break
        }
    }

    /// The mail screens, while the window shows them.
    var split: MailSplitViewController? {
        guard case .mailbox = screen else { return nil }
        return navigator.screens?.split
    }

    /// Moves the window to `next`, filling it with that screen unless only the mail screens' sheet changed. The one
    /// place the window leaves the mail screens: any other screen lets them go, with what they follow.
    func enter(_ next: Screen) {
        let before = screen
        screen = next
        if case .starting(let filled) = before { filled(self) }
        // Whatever replaces a message window waiting out its undo ends the wait.
        if case .leaving(let waiting) = before { waiting.cancel() }
        switch next {
        case .starting, .leaving:
            navigator.leaveScreens()
        case .welcome(let content), .offer(let content), .message(let content, _):
            navigator.leaveScreens()
            show(content)
        case .mailbox:
            guard let split = navigator.screens?.split, drafts.content !== split else { break }
            show(split)
        }
        publishActivity()
    }

    /// Fills the window with `screen`, fading over whatever showed before.
    func show(_ screen: UIViewController) {
        guard drafts.content != nil else {
            drafts.content = screen
            if window.rootViewController == nil { window.rootViewController = drafts }
            return
        }
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
            self.drafts.content = screen
        }
    }

    func topViewController() -> UIViewController? {
        window.topViewController
    }

    /// Signing in over this window, for the service chooser on the welcome screen and in Settings.
    var accountSignIn: AccountSignIn { AccountSignIn(model: model, window: window) }

    func showWelcome() {
        let adder = AccountAdder { [accountSignIn] in try await accountSignIn.signIn(to: $0) }
        adder.onAdded = { [weak self] in self?.showMailbox() }
        enter(.welcome(WelcomeScreen.make(adder: adder, receiveTransfer: transferActions?.receive)))
    }

    /// The mail screens, built afresh for the accounts here, showing what the window shows where it's still here: the
    /// mailboxes beside the list in a wide window or behind it in a narrow one, down to a narrow window back at the
    /// mailboxes; or the conversation alone, in a message window.
    func showMailbox() {
        // The labels the screens on show have read name the new list, which is made before the new mailboxes have
        // read theirs.
        let known = sidebar?.directory.labels ?? []
        // A restored or handed-off thread may be gone from this device, or not on it yet, which the navigator finds
        // off the main actor before anything is built. A message window without it shows the viewer.
        navigator.rebuild(for: model.accounts.map(\.id)) { [weak self] in
            guard let self else { return }
            switch shown.layout {
            case .viewer: showViewer(knowing: known)
            case .message: showMessage(knowing: known)
            }
        }
    }

    /// The thread `shown` opens, alone, from the row the navigator found for it. One whose account is gone leaves the
    /// viewer in its place.
    private func showMessage(knowing known: [MailboxDirectory.Label]) {
        guard let reading = shown.reading else { return showViewer(knowing: known) }
        guard let row = navigator.navigation.foundRow, let reader = reader(for: row, in: reading.mailbox) else {
            navigator.send(.missing(reading.thread))
            return showViewer(knowing: known)
        }
        enter(.message(UINavigationController(rootViewController: reader), built: Appearance(model)))
    }

    /// The viewer's screens, whose lists are named from `known` until the mailboxes have read the labels.
    private func showViewer(knowing known: [MailboxDirectory.Label]) {
        let split = MailSplitViewController(actions: actions)
        split.delegate = self
        // The sheet over the old screens stays up over the rebuilt ones.
        var cover = Cover.none
        if case .mailbox(_, let shownCover) = screen { cover = shownCover }
        // Unowned: the coordinator owns the navigator, which owns the screens and these makers.
        navigator.show(
            in: split,
            making: MailScreens.Makers(
                mailboxes: { [unowned self] in mailboxesViewController(style: $0) },
                list: { [unowned self] in listViewController(for: $0, knowing: known) },
                reader: { [unowned self] reading, row in reader(for: row, in: reading.mailbox) }))
        enter(.mailbox(built: Appearance(model), cover: cover))
        // What waited for the window follows now that the screens fill it.
        navigator.cameOnScreen()
        model.launchAlerts.viewerShowed()
    }

    private func mailboxesViewController(style: MailboxesViewController.Style) -> MailboxesViewController {
        let model = model
        let sidebar = MailboxesViewModel(
            accounts: model.accounts,
            directory: { model.database.mailboxDirectory() },
            smartMailboxes: { model.database.smartMailboxDirectory(mailboxNames: Mailbox.standardNames) },
            navigate: { [weak self] route in self?.handle(route) },
            labelEditor: { model.labelEditor(for: $0) }, smartMailboxStore: model.smartMailboxStore(),
            actions: actions, style: style)
        sidebar.namesChanged = { [weak self] in self?.retitle() }
        return MailboxesViewController(
            viewModel: sidebar,
            syncFooter: SyncFooterSource(health: model.health, accounts: model.accounts) { [weak self] notice in
                await self?.fix(notice)
            })
    }

    func listViewController(for list: WindowState.List, knowing known: [MailboxDirectory.Label]) -> UIViewController {
        switch list {
        case .mailbox(let mailbox): mailboxViewController(for: mailbox, knowing: known)
        case .scheduled: scheduledViewController()
        case .snoozed: snoozedViewController()
        case .smart(let id): smartMailboxViewController(for: id)
        }
    }

    private func scheduledViewController() -> UIViewController {
        let database = model.database
        return WaitingListViewController.scheduled(
            ScheduledViewModel(accounts: model.accounts, messages: { database.scheduledMessages() }, actions: actions))
    }

    private func snoozedViewController() -> UIViewController {
        let database = model.database
        return WaitingListViewController.snoozed(
            SnoozedViewModel(
                accounts: model.accounts, threads: { database.snoozedThreads() }, actions: actions,
                navigate: { [weak self] in self?.handle($0) }))
    }

    /// A reader for `thread` as a list holds it, opened from `mailbox`, or nil when its account is gone.
    func reader(for thread: ThreadSummary, in mailbox: Mailbox) -> ThreadViewController? {
        let id = thread.id
        guard let account = model.accounts.first(where: { $0.id == id.accountID }) else { return nil }
        let model = model
        let viewModel = ThreadViewModel(
            thread: thread,
            mailbox: mailbox,
            accountEmail: account.email,
            accountAliases: account.aliases,
            accountColor: account.color,
            messages: { model.database.messages(inThread: id) },
            pins: { model.database.pinnedThreads() },
            outgoing: { model.database.outgoingMessages(inThread: id) },
            load: { try await model.open(id) },
            attachmentData: { try await model.attachmentData($0, in: $1) },
            source: { try await model.source(of: $0) },
            actions: actions,
            senders: model.senderRules,
            navigate: { [weak self] route in self?.handle(route) },
            storedLabels: { model.database.labels(ofThread: id) },
            placed: { [weak self] in self?.navigator.send(.placed(id, inMailbox: $0)) },
            attachmentsDirectory: model.attachmentsDirectory
        )
        let unsubscriber = model.listUnsubscriber
        let unsubscribeOffer = UnsubscribeOffer(
            account: account.id, accountEmail: account.email,
            perform: { [account] in try await unsubscriber.unsubscribe($0, account: account.id) },
            openURL: { url in UIApplication.shared.open(url) })
        let reader = ThreadViewController(
            viewModel: viewModel, openURL: { url in UIApplication.shared.open(url) },
            unsubscribeOffer: unsubscribeOffer)
        #if canImport(MailIntents)
            reader.userActivity = .reading(thread)
        #endif
        return reader
    }

    private func mailboxViewController(
        for mailbox: Mailbox, knowing known: [MailboxDirectory.Label]
    ) -> MailboxViewController {
        let model = model
        let name = listName(of: mailbox, knowing: known)
        let search = ThreadSearch(
            local: { model.database.search($0, including: $1) }, remote: { try await model.search($0, after: $1) })
        let results = SearchResultsController(
            search: search, accounts: model.accounts, navigate: { [weak self] route in self?.handle(route) },
            readAhead: { model.readAhead($0) }, actions: actions,
            contacts: { [database = model.database] typed in
                do {
                    return try await database.offMain { try $0.contacts(matching: typed, limit: 3) }
                } catch {
                    // The search still shows the mail it finds, without the people.
                    Logger.windows.error("Couldn't read the people to search for: \(error, privacy: .private)")
                    return []
                }
            },
            interaction: window.interactionStyle)
        let list = MailboxViewController(
            viewModel: MailboxViewModel(
                mailbox: mailbox,
                title: name.title,
                naming: name.naming,
                accounts: model.accounts,
                source: source(for: mailbox),
                woken: mailbox.labelID == SystemLabel.inbox ? { model.database.wokenThreads() } : nil,
                pins: { model.database.pinnedThreads() },
                filter: shown.filter,
                didChangeFilter: { [weak self] filter in self?.navigator.send(.filter(filter)) },
                attachmentThreads: { model.database.threadsHoldingAttachments() },
                sidebar: { [weak self] in self?.sidebar },
                refresh: { try await model.syncAll() },
                retryAlerts: { await model.refreshPush() },
                older: .pages { try await model.loadOlder(mailbox) },
                navigate: { [weak self] route in self?.handle(route) },
                readAhead: { model.readAhead($0) },
                actions: actions,
                senders: model.senderRules,
                conversationSources: ConversationSources(
                    messages: { try await model.messagesToAnswer(in: $0).map(\.id) },
                    source: { try await model.source(of: $0) }),
                interaction: window.interactionStyle,
                health: model.health
            ),
            searchResults: results, draftsDock: drafts.dock)
        return list
    }

    /// An Inbox split into Gmail's categories when any account in it sorts it, opening on the one last shown; any
    /// other mailbox as one list. An account whose service has no categories counts as unsorted, so its whole Inbox
    /// is in Primary.
    private func source(for mailbox: Mailbox) -> MailboxSource {
        let database = model.database
        let unsorted = model.unsortedInboxAccounts
        let accounts = model.accounts.filter { mailbox.accountID == nil || mailbox.accountID == $0.id }
        guard mailbox.labelID == SystemLabel.inbox, accounts.contains(where: { !unsorted.contains($0.id) }) else {
            return .flat(.windowed { database.threads(in: mailbox, window: $0) })
        }
        let categories = InboxCategories(
            threads: { database.threads(in: mailbox, category: $0, unsorted: unsorted, window: $1) },
            unreadCounts: { database.categoryUnreadCounts(in: mailbox, unsorted: unsorted) },
            didSelect: { [weak self] category in self?.navigator.send(.category(category)) })
        return .categorised(categories, selected: shown.category)
    }

    /// The one place navigation happens (ADR-011): each route goes through the window's navigation, which moves what it
    /// shows or has a screen presented (`present(_:)`). A route from outside uncovers the window first
    /// (`WindowNavigation.Effect.uncover`); from inside, a new list or search shows over the message being written,
    /// which goes down to the drafts pill first.
    func handle(_ route: Route, from source: RouteSource = .window) {
        switch (route, source) {
        case (.mailbox, .window), (.smartMailbox, .window), (.search, .window):
            drafts.uncover { [weak self] in self?.navigator.send(.route(route)) }
        default:
            navigator.send(.route(route, from: source))
        }
    }

    /// Opens `draft` where this window opens new messages: in its composer, or in a window of its own. What was
    /// dropped for it, `loaded`, goes in once it is open.
    func compose(_ draft: Draft, holding loaded: SharedItems.Loaded? = nil) {
        switch window.interactionStyle.composePlacement {
        case .sheet: composeHere(draft, holding: loaded)
        case .ownWindow: openComposeWindow(for: draft, holding: loaded)
        }
    }

    /// Opens `draft` in this window's composer, over the mail screens, with what was dropped for it, `loaded`, once it
    /// is open.
    func composeHere(_ draft: Draft, holding loaded: SharedItems.Loaded? = nil) {
        guard let composer = composer(for: draft) else { return }
        if let loaded { composer.whenOpen { [weak composer] in composer?.receive(loaded) } }
        drafts.open(composer)
    }

    /// A composer for `draft` in this window, which can move into a window of its own, or `nil` once its account is
    /// gone.
    func composer(for draft: Draft) -> ComposeViewController? {
        let composer = model.composer(for: draft, actions: actions)
        composer?.openInOwnWindow = { [weak self] in self?.openComposeWindow(for: $0) }
        return composer
    }
}

extension SceneCoordinator {
    /// What the window shows, for the system to save with the scene and restore with it, and to offer to the
    /// reader's other devices.
    var activity: NSUserActivity? {
        showsMail ? shown.activity : nil
    }

    /// Whether the window shows mail: the mail screens, or one conversation, even while it waits out an undo.
    var showsMail: Bool {
        switch screen {
        case .mailbox, .message, .leaving: true
        case .starting, .welcome, .offer: false
        }
    }

    /// Makes the window's activity current, so Handoff offers what it shows now, and names the window after it.
    func publishActivity() {
        window.windowScene?.userActivity = activity
        window.windowScene?.userActivity?.becomeCurrent()
        retitle()
    }
}

extension Logger {
    /// What a window couldn't read for what it shows, as a picker's labels or a list's name.
    nonisolated static let windows = Logger(subsystem: "com.idanbirman.goodmail", category: "windows")
}
