import ICloudProvider
import MailCore
import MailStore
import MailUI
import UIKit

/// One per window (ADR-011): decides what the window shows and owns the flows that change it.
final class SceneCoordinator: NSObject {
    private let window: UIWindow
    private let model: AppModel
    private let actions: MailActions
    private var failures: Task<Void, Never>?
    /// Failed sends already shown, so each is offered once per launch.
    private var shownFailures: Set<Draft.ID> = []
    /// The mail screens, once there is an account.
    private var split: MailSplitViewController?
    /// What the mail screens show, kept so either arrangement can be rebuilt when the window changes width, and
    /// saved for the system to restore the window or hand it off (`activity`).
    private var shown: WindowState {
        didSet { if shown != oldValue { publishActivity() } }
    }

    /// `restoring` is what the window showed when the system last saved it, or what another device handed off.
    init(window: UIWindow, model: AppModel, restoring: WindowState?) {
        self.window = window
        self.model = model
        shown = restoring?.keeping(model.accounts.map(\.id)) ?? WindowState()
        actions = MailActions(commands: model.commands)
        super.init()
        actions.reopen = { [weak self] draft in self?.handle(.compose(draft)) }
    }

    deinit {
        failures?.cancel()
    }

    func start() {
        if model.accounts.isEmpty {
            showWelcome()
        } else {
            showMailbox(shown)
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

    /// Accounts and preferences. The mail screens are rebuilt once it closes if the accounts or how they look changed.
    private func showSettings() {
        guard let presenter = topViewController() else { return }
        let model = model
        let before = model.accounts
        let unsortedBefore = Preferences.unsortedInboxAccounts
        let displayBefore = Preferences.rowDisplay
        let themeBefore = Preferences.combinedTheme
        let viewModel = SettingsViewModel(
            accounts: { model.accounts },
            signIn: { [weak self] in try await self?.signIn(to: $0) ?? false },
            remove: { try await model.removeAccount($0) },
            update: { try await model.update($0) },
            closed: { [weak self] in
                guard let self,
                    model.accounts != before || Preferences.unsortedInboxAccounts != unsortedBefore
                        || Preferences.rowDisplay != displayBefore || Preferences.combinedTheme != themeBefore
                else { return }
                model.accounts.isEmpty ? showWelcome() : showMailbox()
            })
        presenter.present(SettingsScreen.make(model: viewModel), animated: true)
    }

    private func topViewController() -> UIViewController? {
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    /// Signs in to `service` and adds its account, for the service chooser on the welcome screen and in Settings.
    /// Returns `false` if the reader cancelled. A service whose sign-in is a web page goes through `AppModel`; one that
    /// needs its own form presents it here, over the chooser.
    private func signIn(to service: MailService) async throws -> Bool {
        switch service {
        case .gmail: try await model.addGmailAccount(using: WebAuthentication(window: window))
        case .icloud: await signInToICloud()
        case .outlook: try await model.addOutlookAccount(using: WebAuthentication(window: window))
        }
    }

    /// Presents the iCloud form over the chooser, and returns whether it added the account.
    private func signInToICloud() async -> Bool {
        await withCheckedContinuation { continuation in
            weak var presented: UIViewController?
            let screen = ICloudSignInScreen.make(
                signIn: { [model] email, appPassword in
                    do {
                        try await model.addICloudAccount(email: email, appPassword: appPassword)
                    } catch ICloudSignIn.Failure.wrongPassword {
                        throw ICloudSignInFailure.wrongPassword
                    }
                },
                finished: { added in
                    presented?.dismiss(animated: true)
                    continuation.resume(returning: added)
                })
            presented = screen
            guard let top = topViewController() else { return continuation.resume(returning: false) }
            top.present(screen, animated: true)
        }
    }

    private func showWelcome() {
        let adder = AccountAdder { [weak self] in try await self?.signIn(to: $0) ?? false }
        adder.onAdded = { [weak self] in self?.showMailbox() }
        split = nil
        window.rootViewController = WelcomeScreen.make(adder: adder)
        publishActivity()
    }

    /// `state`, the Inbox unless a restored window says otherwise, with the mailboxes beside it in a wide window or
    /// behind it in a narrow one.
    private func showMailbox(_ state: WindowState = WindowState()) {
        shown = state
        // A restored or handed-off thread may be gone from this device, or not on it yet.
        if let thread = shown.openThread?.id, (try? model.database.thread(thread)) == nil { shown.setThread(nil) }
        let split = MailSplitViewController(actions: actions)
        split.delegate = self
        self.split = split
        buildColumns()
        buildStack()
        if window.rootViewController == nil {
            window.rootViewController = split
        } else {
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                self.window.rootViewController = split
            }
        }
        publishActivity()
    }

    private func mailboxesViewController(style: MailboxesViewController.Style) -> MailboxesViewController {
        let model = model
        let mailboxes = MailboxesViewController(
            viewModel: MailboxesViewModel(
                accounts: model.accounts,
                directory: { model.database.mailboxDirectory() },
                navigate: { [weak self] route in self?.handle(route) }),
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
        let stack = UINavigationController(rootViewController: mailboxesViewController(style: .list))
        stack.delegate = self
        stack.pushViewController(shownListViewController(), animated: false)
        if let reader = shownReader() { stack.pushViewController(reader, animated: false) }
        split.setViewController(stack, for: .compact)
    }

    private func shownListViewController() -> UIViewController {
        switch shown.list {
        case .mailbox(let mailbox, let title, _): mailboxViewController(for: mailbox, title: title)
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
            accountColor: account.color,
            accountService: account.service,
            messages: { model.database.messages(inThread: id) },
            load: { try await model.open(id) },
            attachmentData: { try await model.attachmentData($0, in: $1) },
            actions: actions,
            navigate: { [weak self] route in self?.handle(route) },
            close: { [weak self] in self?.closeThread() },
            attachmentsDirectory: model.attachmentsDirectory
        )
        return ThreadViewController(viewModel: viewModel, openURL: { url in UIApplication.shared.open(url) })
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

    private func mailboxViewController(for mailbox: Mailbox, title: String?) -> MailboxViewController {
        let model = model
        let search = ThreadSearch(
            local: { model.database.search($0, including: $1) }, remote: { try await model.search($0, after: $1) })
        let results = SearchResultsController(
            search: search, accounts: model.accounts, navigate: { [weak self] route in self?.handle(route) },
            actions: actions, contacts: { (try? model.database.contacts(matching: $0, limit: 3)) ?? [] })
        return MailboxViewController(
            viewModel: MailboxViewModel(
                mailbox: mailbox,
                title: title,
                accounts: model.accounts,
                source: source(for: mailbox),
                woken: mailbox.labelID == SystemLabel.inbox ? { model.database.wokenThreads() } : nil,
                refresh: { try await model.syncAll() },
                loadOlder: { try await model.loadOlder(mailbox) },
                navigate: { [weak self] route in self?.handle(route) },
                actions: actions
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

    /// The one place navigation happens (ADR-011).
    func handle(_ route: Route) {
        switch route {
        case .mailbox(let mailbox):
            let labels = (try? model.database.labels(for: mailbox.accountID ?? AccountID(rawValue: ""))) ?? []
            let title = labels.first { $0.id == mailbox.labelID }?.name
            show(.mailbox(mailbox, title: title, thread: nil))
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
            UIApplication.shared.requestSceneSessionActivation(
                nil, userActivity: shown.opening(id, in: mailbox).activity, options: options, errorHandler: nil)
        case .changeLabels(let ids):
            let threads = ids.compactMap { try? model.database.thread($0) }
            guard let account = threads.first?.id.accountID,
                let labels = try? model.database.labels(for: account),
                let presenter = topViewController()
            else { return }
            let actions = actions
            let picker = LabelPickerViewController(labels: labels, threads: threads) { action in
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
                    threads: ids, from: mailbox, labels: { (try? database.labels(for: $0)) ?? [] }, actions: actions))
            let navigation = UINavigationController(rootViewController: picker)
            navigation.sheetPresentationController?.detents = [.medium(), .large()]
            presenter.present(navigation, animated: true)
        case .settings:
            showSettings()
        case .compose(let draft):
            guard let account = model.accounts.first(where: { $0.id == draft.accountID }),
                let presenter = topViewController()
            else { return }
            let actions = actions
            let suggester = RecipientSuggester(
                writtenIn: { [database = model.database] in try database.contacts(matching: $0) },
                addressBook: SystemAddressBook())
            let composer = ComposeViewController(
                viewModel: ComposeViewModel(
                    draft: draft, accountEmail: account.email, senders: model.accounts,
                    signature: { [database = model.database] in try? database.signature(for: $0) },
                    suggest: { await suggester.suggestions(for: $0) },
                    saveDraft: { actions.saveDraft($0) }, deleteDraft: { actions.deleteDraft($0) },
                    send: { actions.send($0, at: $1) }))
            let navigation = UINavigationController(rootViewController: composer)
            navigation.modalPresentationStyle = .pageSheet
            presenter.present(navigation, animated: true)
        }
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
            split.show(.supplementary)
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
        if navigationController.viewControllers.count == 1 { shown = WindowState(category: shown.category) }
    }
}

extension WindowState {
    /// The state as an activity, which restores it, hands it off, or opens it in a new window.
    fileprivate var activity: NSUserActivity? {
        guard let saved = try? saved() else { return nil }
        let activity = NSUserActivity(activityType: Self.activityType)
        activity.userInfo = [Self.activityKey: saved]
        activity.isEligibleForHandoff = true
        return activity
    }

    /// Where the mailboxes list marks the reader as being.
    fileprivate var destination: MailboxesViewModel.Destination {
        switch list {
        case .mailbox(let mailbox, _, _): .mailbox(mailbox)
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

    /// Makes the window's activity current, so Handoff offers what it shows now.
    private func publishActivity() {
        window.windowScene?.userActivity = activity
        window.windowScene?.userActivity?.becomeCurrent()
    }

    /// Shows what another device handed off, in this window.
    func showHandedOff(_ state: WindowState) {
        guard !model.accounts.isEmpty else { return }
        showMailbox(state.keeping(model.accounts.map(\.id)))
    }
}
