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
    let window: UIWindow
    let model: AppModel
    private let actions: MailActions
    private var failures: Task<Void, Never>?
    /// The launch check for a Gmail sign-in that can't delete forever, or signing an account in again.
    private var signingInAgain: Task<Void, Never>?
    /// An answer from the list waiting for the message it answers, which a newer answer replaces.
    private var answering: Task<Void, Never>?
    /// Failed sends already shown, so each is offered once per launch.
    private var shownFailures: Set<Draft.ID> = []
    /// What fills the window. Only `enter(_:)` changes it.
    private(set) var screen = Screen.starting
    /// Follow each pass that brings this device's accounts and settings in step with the reader's other devices.
    var deviceObservers: [any NSObjectProtocol] = []
    /// The screen receiving accounts from another device, so a code the Camera app opens while it's up goes to it.
    var receivingTransfer: ReceivingTransfer?
    /// The window's root, which holds the mail screens and the messages minimized below them.
    private let drafts = DraftShelfViewController()
    /// Names this window's minimized messages in the database. Fresh each launch, so the next one finds them unclaimed.
    private let windowID = UUID().uuidString
    /// What the mail screens show, kept so either arrangement can be rebuilt when the window changes width, and
    /// saved for the system to restore the window or hand it off (`activity`).
    private var shown: WindowState {
        didSet { if shown != oldValue { publishActivity() } }
    }

    /// The thread the window is reading, for Get Open Conversation.
    var openThread: ThreadSummary.ID? { shown.openThread?.id }

    /// `restoring` is what the window showed when the system last saved it, or what another device handed off.
    init(windowScene: UIWindowScene, model: AppModel, restoring: WindowState?) {
        self.model = model
        shown = restoring?.keeping(model.accounts.map(\.id)) ?? WindowState()
        let actions = MailActions(commands: model.commands)
        self.actions = actions
        window = ShakeToUndoWindow(windowScene: windowScene, undo: { actions.undoLast() })
        window.traitOverrides.senderPictures = model.senderPictures
        super.init()
        actions.reopen = { [weak self] draft in self?.handle(.compose(draft)) }
        drafts.newMessage = { [weak self] account in self?.handle(.compose(Draft(accountID: account))) }
        drafts.keep = { [minimized = model.minimizedDrafts, window = windowID] in minimized.keep($0, for: window) }
    }

    isolated deinit {
        for observer in deviceObservers { NotificationCenter.default.removeObserver(observer) }
        failures?.cancel()
        signingInAgain?.cancel()
        answering?.cancel()
    }

    /// The window is going away; another window may take its minimized messages.
    func close() {
        model.minimizedDrafts.close(windowID)
    }

    func start() {
        observeSharedAccounts()
        observeSyncedSettings()
        if model.accounts.isEmpty {
            // A new device whose reader has accounts on another one, or a reinstall, offers those first.
            if model.accountOffer == nil { showWelcome() } else { offerSharedAccounts() }
        } else {
            showMailbox(shown)
            checkGmailSignIns()
            model.minimizedDrafts.claim(for: windowID) { [weak self] minimized in
                guard let self else { return }
                drafts.restore(minimized.compactMap { self.composer(for: $0) })
            }
        }
        failures = Task { [weak self, database = model.database] in
            do {
                for try await failed in database.failedMessages() {
                    self?.showFailure(of: failed)
                }
            } catch {}
        }
    }

    /// Offers the first failed send that hasn't been shown: edit it, try it again, or delete it.
    private func showFailure(of failed: [OutgoingMessage]) {
        guard let message = failed.first(where: { !shownFailures.contains($0.id) }),
            let presenter = topViewController(), !(presenter is UIAlertController)
        else { return }
        shownFailures.insert(message.id)
        let actions = actions
        let alert = SendFailureAlert.make(
            for: message,
            edit: { actions.discardSend(message, edit: true) },
            retry: { actions.retrySend(message) },
            delete: { actions.discardSend(message) })
        presenter.present(alert, animated: true)
    }

    /// Once a launch, asks the first Gmail account whose sign-in can't delete forever to sign in again.
    private func checkGmailSignIns() {
        signingInAgain = Task { [weak self, model] in
            guard let account = await model.gmailAccountsToSignInAgain().first,
                let self, let presenter = topViewController(), !(presenter is UIAlertController)
            else { return }
            let alert = UIAlertController.signInAgainToDeleteForever(account.email) { [weak self] in
                self?.signInAgain(account.id)
            }
            presenter.present(alert, animated: true)
        }
    }

    /// Signs `id` in again, its new sign-in replacing the old one and keeping the account. Replaces a launch check
    /// or a sign-in already under way.
    private func signInAgain(_ id: AccountID) {
        guard let account = model.accounts.first(where: { $0.id == id }) else { return }
        signingInAgain?.cancel()
        signingInAgain = Task { [weak self] in await self?.signIn(againTo: account) }
    }

    /// The mail screens, while the window shows them.
    var split: MailSplitViewController? {
        guard case .mailbox(let split, _, _) = screen else { return nil }
        return split
    }

    /// Moves the window to `next`, filling it with that screen unless only the mail screens' sheet changed.
    func enter(_ next: Screen) {
        let before = screen
        screen = next
        switch next {
        case .starting: break
        case .welcome(let content), .offer(let content): show(content)
        case .mailbox(let split, _, _):
            if case .mailbox(let shown, _, _) = before, shown === split { return }
            show(split)
        }
        publishActivity()
    }

    /// Fills the window with `screen`, fading over whatever showed before.
    private func show(_ screen: UIViewController) {
        guard window.rootViewController != nil else {
            drafts.content = screen
            window.rootViewController = drafts
            return
        }
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
            self.drafts.content = screen
        }
    }

    func topViewController() -> UIViewController? {
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    /// Signs in to `service` and adds its account, for the service chooser on the welcome screen and in Settings.
    /// Returns `false` if the reader cancelled. A service whose sign-in is a web page goes through `AppModel`; one that
    /// needs its own form presents it here, over the chooser.
    func signIn(to service: MailService) async throws -> Bool {
        switch service {
        case .gmail: try await model.addGmailAccount(using: web)
        case .icloud: await signInToICloud()
        case .outlook: try await model.addOutlookAccount(using: web)
        case .imap: await signInToOtherAccount()
        }
    }

    /// The web sign-in, over this window.
    var web: WebAuthentication { WebAuthentication(window: window) }

    /// Presents the iCloud form over the chooser, and returns whether it added the account.
    /// `email` fills the address in, as when iCloud stopped accepting an account's password.
    func signInToICloud(email: String = "") async -> Bool {
        await presentSignIn { [model] finished in
            ICloudSignInScreen.make(
                email: email,
                signIn: { email, appPassword in
                    do {
                        try await model.addICloudAccount(email: email, appPassword: appPassword)
                    } catch ICloudSignIn.Failure.wrongPassword {
                        throw ICloudSignInFailure.wrongPassword
                    }
                },
                finished: finished)
        }
    }

    /// Presents a sign-in form `screen` makes over the chooser, and returns what the form finished with: whether it
    /// added the account. The form calls `finished` once.
    func presentSignIn(_ screen: (_ finished: @escaping (Bool) -> Void) -> UIViewController) async -> Bool {
        await withCheckedContinuation { continuation in
            weak var presented: UIViewController?
            let form = screen { added in
                presented?.dismiss(animated: true)
                continuation.resume(returning: added)
            }
            presented = form
            guard let top = topViewController() else { return continuation.resume(returning: false) }
            top.present(form, animated: true)
        }
    }

    func showWelcome() {
        let adder = AccountAdder { [weak self] in try await self?.signIn(to: $0) ?? false }
        adder.onAdded = { [weak self] in self?.showMailbox() }
        enter(.welcome(WelcomeScreen.make(adder: adder, receiveTransfer: transferActions?.receive)))
    }

    /// `state`, the Inbox unless a restored window says otherwise, with the mailboxes beside it in a wide window or
    /// behind it in a narrow one.
    func showMailbox(_ state: WindowState = WindowState()) {
        shown = state
        // A restored or handed-off thread may be gone from this device, or not on it yet.
        if let thread = shown.openThread?.id, (try? model.database.thread(thread)) == nil { shown.setThread(nil) }
        let split = MailSplitViewController(actions: actions)
        split.delegate = self
        // The sheet over the old screens stays up over the rebuilt ones.
        var cover = Cover.none
        if case .mailbox(_, _, let shownCover) = screen { cover = shownCover }
        enter(.mailbox(split, accounts: model.accounts.map(\.id), cover: cover))
        buildColumns()
        buildStack()
    }

    private func mailboxesViewController(style: MailboxesViewController.Style) -> MailboxesViewController {
        let model = model
        let mailboxes = MailboxesViewController(
            viewModel: MailboxesViewModel(
                accounts: model.accounts,
                directory: { model.database.mailboxDirectory() },
                navigate: { [weak self] route in self?.handle(route) },
                labelEditor: { model.labelEditor(for: $0) }),
            style: style)
        mailboxes.selected = shown.destination
        return mailboxes
    }

    /// The wide arrangement: the mailboxes as a sidebar, the shown mailbox's list, and its open thread.
    private func buildColumns() {
        guard let split else { return }
        split.setViewController(
            UINavigationController(rootViewController: mailboxesViewController(style: .sidebar)), for: .primary)
        split.setViewController(
            UINavigationController(rootViewController: shownListViewController()), for: .supplementary)
        split.setViewController(
            UINavigationController(rootViewController: shownReader() ?? NoThreadViewController()), for: .secondary)
    }

    /// The narrow arrangement: one stack of the mailboxes, the shown mailbox's list and its open thread.
    private func buildStack() {
        guard let split else { return }
        let stack = MailStackController(rootViewController: mailboxesViewController(style: .list))
        stack.delegate = self
        switch shown.depth {
        case .mailboxes:
            break
        case .list:
            stack.pushViewController(shownListViewController(), animated: false)
            if let reader = shownReader() { stack.pushViewController(reader, animated: false) }
        }
        split.setViewController(stack, for: .compact)
    }

    private func shownListViewController() -> UIViewController {
        switch shown.list {
        case .mailbox(let mailbox, _): mailboxViewController(for: mailbox)
        case .scheduled: scheduledViewController()
        case .snoozed: snoozedViewController()
        }
    }

    /// A reader for the thread open from the shown list, if one is and it is still there.
    private func shownReader() -> ThreadViewController? {
        shown.openThread.flatMap { reader(for: $0.id, in: $0.mailbox) }
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

    private func navigation(for column: UISplitViewController.Column) -> UINavigationController? {
        split?.viewController(for: column) as? UINavigationController
    }

    /// A reader for the thread, opened from `mailbox`, or nil when it is gone.
    private func reader(for id: ThreadSummary.ID, in mailbox: Mailbox) -> ThreadViewController? {
        guard let thread = try? model.database.thread(id),
            let account = model.accounts.first(where: { $0.id == id.accountID })
        else { return nil }
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
            navigate: { [weak self] route in self?.handle(route) },
            close: { [weak self] in self?.closeThread() },
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

    /// Leaves the open thread, after an action that takes it out of the mailbox.
    private func closeThread() {
        guard let split else { return }
        shown.setThread(nil)
        if split.isCollapsed {
            navigation(for: .compact)?.popViewController(animated: true)
        } else {
            navigation(for: .secondary)?.setViewControllers([NoThreadViewController()], animated: false)
        }
    }

    private func mailboxViewController(for mailbox: Mailbox) -> MailboxViewController {
        let model = model
        let labels = labels(naming: mailbox)
        let search = ThreadSearch(
            local: { model.database.search($0, including: $1) }, remote: { try await model.search($0, after: $1) })
        let results = SearchResultsController(
            search: search, accounts: model.accounts, navigate: { [weak self] route in self?.handle(route) },
            actions: actions, contacts: { (try? model.database.contacts(matching: $0, limit: 3)) ?? [] })
        return MailboxViewController(
            viewModel: MailboxViewModel(
                mailbox: mailbox,
                title: mailbox.listTitle(labels: labels, accounts: model.accounts),
                accounts: model.accounts,
                source: source(for: mailbox),
                woken: mailbox.labelID == SystemLabel.inbox ? { model.database.wokenThreads() } : nil,
                pins: { model.database.pinnedThreads() },
                refresh: { try await model.syncAll() },
                loadOlder: { try await model.loadOlder(mailbox) },
                navigate: { [weak self] route in self?.handle(route) },
                actions: actions,
                health: model.health
            ),
            searchResults: results)
    }

    /// An Inbox split into Gmail's categories when any account in it sorts it, opening on the one last shown; any
    /// other mailbox as one list. An account whose service has no categories counts as unsorted, so its whole Inbox
    /// is in Primary.
    private func source(for mailbox: Mailbox) -> MailboxSource {
        let database = model.database
        let unsorted = Preferences.unsortedInboxAccounts.union(
            model.accounts.filter { !$0.service.hasInboxCategories }.map(\.id))
        let accounts = model.accounts.filter { mailbox.accountID == nil || mailbox.accountID == $0.id }
        guard mailbox.labelID == SystemLabel.inbox, accounts.contains(where: { !unsorted.contains($0.id) }) else {
            return .flat { database.threads(in: mailbox) }
        }
        let categories = InboxCategories(
            threads: { database.threads(in: mailbox, category: $0, unsorted: unsorted) },
            unreadCounts: { database.categoryUnreadCounts(in: mailbox, unsorted: unsorted) },
            didSelect: { [weak self] in self?.shown.category = $0 })
        return .categorised(categories, selected: shown.category)
    }

    /// Opens a `mailto:` link in the composer, from the first account. Without an account there is nothing to send
    /// from, so the welcome screen stays.
    func compose(mailto link: URL) {
        guard let account = model.accounts.first?.id, let draft = Draft(mailto: link, from: account) else { return }
        handle(.compose(draft))
    }

    /// The one place navigation happens (ADR-011).
    func handle(_ route: Route) {
        switch route {
        case .mailbox(let mailbox):
            show(.mailbox(mailbox, thread: nil))
        case .scheduled:
            show(.scheduled)
        case .snoozed:
            show(.snoozed(thread: nil))
        case .thread(let id, let mailbox):
            guard let split, let reader = reader(for: id, in: mailbox) else { return }
            shown.setThread(id)
            if split.isCollapsed {
                navigation(for: .compact)?.pushViewController(reader, animated: true)
            } else {
                navigation(for: .secondary)?.setViewControllers([reader], animated: false)
                split.show(.secondary)
            }
        case .newWindow(let id, let mailbox):
            let options = UIScene.ActivationRequestOptions()
            options.requestingScene = window.windowScene
            var request = UISceneSessionActivationRequest()
            request.userActivity = shown.opening(id, in: mailbox).activity
            request.options = options
            // iPhone Duo opens new windows only on its inner display, so closed, the thread opens here instead. UIKit
            // doesn't say which queue the handler runs on; the hop to the main actor is all it does, and it ends there.
            UIApplication.shared.activateSceneSession(for: request) { @Sendable [weak self] _ in
                Task { @MainActor in self?.handle(.thread(id, in: mailbox)) }
            }
        case .changeLabels(let ids):
            let threads = ids.compactMap { try? model.database.thread($0) }
            guard let account = threads.first?.id.accountID,
                let labels = try? model.database.labels(for: account),
                let presenter = topViewController()
            else { return }
            let actions = actions
            let picker = LabelPickerViewController(
                labels: labels, threads: threads, editor: model.labelEditor(for: account)
            ) { action in
                actions.perform(action, on: ids)
            }
            let navigation = UINavigationController(rootViewController: picker)
            navigation.sheetPresentationController?.detents = [.medium(), .large()]
            presenter.present(navigation, animated: true)
        case .move(let ids, let mailbox):
            guard let presenter = topViewController() else { return }
            let database = model.database
            let picker = MoveViewController(
                viewModel: MoveViewModel(
                    threads: ids, from: mailbox, labels: { (try? database.labels(for: $0)) ?? [] },
                    editor: { [model] in model.labelEditor(for: $0) }, actions: actions))
            let navigation = UINavigationController(rootViewController: picker)
            navigation.sheetPresentationController?.detents = [.medium(), .large()]
            presenter.present(navigation, animated: true)
        case .settings(let page):
            showSettings(at: page)
        case .signInAgain(let id):
            signInAgain(id)
        case .answer(let id, let answer):
            guard let account = model.accounts.first(where: { $0.id == id.accountID }) else { return }
            answering?.cancel()
            answering = Task { [weak self, model] in
                let draft = try? await answer.draft(
                    answering: model.messagesToAnswer(in: id), accountEmail: account.email, aliases: account.aliases,
                    wording: .localized)
                guard !Task.isCancelled, let self else { return }
                if let draft {
                    handle(.compose(draft))
                } else {
                    topViewController()?.present(UIAlertController.answerUnavailable(), animated: true)
                }
            }
        case .compose(let draft):
            guard let composer = composer(for: draft) else { return }
            drafts.open(composer)
        }
    }

    /// A composer for `draft`, or `nil` once its account is gone.
    private func composer(for draft: Draft) -> ComposeViewController? {
        guard let account = model.accounts.first(where: { $0.id == draft.accountID }) else { return nil }
        let actions = actions
        let suggester = RecipientSuggester(
            writtenIn: { [database = model.database] in try database.contacts(matching: $0) },
            addressBook: SystemAddressBook())
        return ComposeViewController(
            viewModel: ComposeViewModel(
                draft: draft, accountEmail: account.email, senders: model.accounts,
                signature: { [database = model.database] in try? database.signature(for: $0) },
                suggest: { await suggester.suggestions(for: $0) },
                saveDraft: { actions.saveDraft($0, $1) }, deleteDraft: { actions.deleteDraft($0) },
                send: { actions.send($0, at: $1) }))
    }
}

extension SceneCoordinator {
    /// Shows `list` beside the mailboxes, with no thread open.
    private func show(_ list: WindowState.List) {
        guard let split else { return }
        shown = WindowState(list: list, category: shown.category)
        let controller = shownListViewController()
        if split.isCollapsed {
            navigation(for: .compact)?.pushViewController(controller, animated: true)
        } else {
            navigation(for: .supplementary)?.setViewControllers([controller], animated: false)
            navigation(for: .secondary)?.setViewControllers([NoThreadViewController()], animated: false)
            (navigation(for: .primary)?.viewControllers.first as? MailboxesViewController)?.selected =
                shown.destination
            split.showList()
        }
    }
}

extension SceneCoordinator: UISplitViewControllerDelegate, UINavigationControllerDelegate {
    // Each arrangement is rebuilt from what was shown in the other, so the open mailbox and thread carry over.
    func splitViewControllerDidCollapse(_ splitViewController: UISplitViewController) {
        buildStack()
    }

    func splitViewControllerDidExpand(_ splitViewController: UISplitViewController) {
        buildColumns()
    }

    /// Keeps `shown` in step as the narrow stack is popped back.
    func navigationController(
        _ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool
    ) {
        if !navigationController.viewControllers.contains(where: { $0 is ThreadViewController }) {
            shown.setThread(nil)
        }
        if navigationController.viewControllers.count == 1 {
            shown = WindowState(category: shown.category, depth: .mailboxes)
        }
    }
}

extension WindowState {
    /// Where the mailboxes list marks the reader as being.
    fileprivate var destination: MailboxesViewModel.Destination {
        switch list {
        case .mailbox(let mailbox, _): .mailbox(mailbox)
        case .scheduled: .scheduled
        case .snoozed: .snoozed
        }
    }
}

extension SceneCoordinator {
    /// What the window shows, for the system to save with the scene and restore with it, and to offer to the
    /// reader's other devices.
    var activity: NSUserActivity? {
        split == nil ? nil : shown.activity
    }

    /// Makes the window's activity current, so Handoff offers what it shows now, and names the window after it.
    private func publishActivity() {
        window.windowScene?.userActivity = activity
        window.windowScene?.userActivity?.becomeCurrent()
        window.windowScene?.title = split == nil ? nil : title(of: shown)
    }

    /// Rebuilds the mail screens for the accounts here now, keeping what they show where it's still here, down to a
    /// narrow window that was back at the mailboxes rather than in a list.
    func showMailboxKeepingPlace() {
        showMailbox(shown.keeping(model.accounts.map(\.id)))
    }

    /// Shows what another device handed off, in this window.
    func showHandedOff(_ state: WindowState) {
        guard !model.accounts.isEmpty else { return }
        showMailbox(state.keeping(model.accounts.map(\.id)))
    }
}
