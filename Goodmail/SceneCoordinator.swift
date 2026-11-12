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
    /// What the mail screens show, kept so either arrangement can be rebuilt when the window changes width.
    private var shown = Shown()

    private struct Shown {
        var mailbox = Mailbox.inbox
        var title: String?
        var thread: ThreadSummary.ID?
    }

    init(window: UIWindow, model: AppModel) {
        self.window = window
        self.model = model
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
            showMailbox()
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
        let commands = model.commands
        let alert = SendFailureAlert.make(
            for: message,
            edit: { [weak self] in
                guard (try? commands.discardSend(message.id)) != nil else { return }
                self?.handle(.compose(message.draft))
            },
            retry: { try? commands.retrySend(message) },
            delete: { try? commands.discardSend(message.id) })
        presenter.present(alert, animated: true)
    }

    /// Accounts and preferences. The mail screens are rebuilt once it closes if the accounts changed.
    private func showSettings() {
        guard let presenter = topViewController() else { return }
        let model = model
        let before = model.accounts.map(\.id)
        let viewModel = SettingsViewModel(
            accounts: { model.accounts },
            add: { [weak self] in
                guard let self else { return false }
                return try await model.addGmailAccount(using: WebAuthentication(window: window))
            },
            remove: { try await model.removeAccount($0) },
            closed: { [weak self] in
                guard let self, model.accounts.map(\.id) != before else { return }
                model.accounts.isEmpty ? showWelcome() : showMailbox()
            })
        presenter.present(SettingsScreen.make(model: viewModel), animated: true)
    }

    private func topViewController() -> UIViewController? {
        var top = window.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }

    private func showWelcome() {
        let welcome = WelcomeViewController { [weak self] in
            guard let self else { return }
            if try await model.addGmailAccount(using: WebAuthentication(window: window)) {
                showMailbox()
            }
        }
        window.rootViewController = UINavigationController(rootViewController: welcome)
    }

    /// The Inbox, with the mailboxes beside it in a wide window or behind it in a narrow one.
    private func showMailbox() {
        shown = Shown()
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
    }

    private func mailboxesViewController(style: MailboxesViewController.Style) -> MailboxesViewController {
        let model = model
        let mailboxes = MailboxesViewController(
            viewModel: MailboxesViewModel(
                accounts: model.accounts,
                directory: { model.database.mailboxDirectory() },
                navigate: { [weak self] route in self?.handle(route) }),
            style: style)
        mailboxes.selectedMailbox = shown.mailbox
        return mailboxes
    }

    /// The wide arrangement: the mailboxes as a sidebar, the shown mailbox's list, and its open thread.
    private func buildColumns() {
        guard let split else { return }
        split.setViewController(
            UINavigationController(rootViewController: mailboxesViewController(style: .sidebar)), for: .primary)
        split.setViewController(
            UINavigationController(rootViewController: mailboxViewController(for: shown.mailbox, title: shown.title)),
            for: .supplementary)
        split.setViewController(
            UINavigationController(rootViewController: shown.thread.flatMap(reader(for:)) ?? NoThreadViewController()),
            for: .secondary)
    }

    /// The narrow arrangement: one stack of the mailboxes, the shown mailbox's list and its open thread.
    private func buildStack() {
        guard let split else { return }
        let stack = UINavigationController(rootViewController: mailboxesViewController(style: .list))
        stack.delegate = self
        stack.pushViewController(mailboxViewController(for: shown.mailbox, title: shown.title), animated: false)
        if let reader = shown.thread.flatMap(reader(for:)) { stack.pushViewController(reader, animated: false) }
        split.setViewController(stack, for: .compact)
    }

    private func navigation(for column: UISplitViewController.Column) -> UINavigationController? {
        split?.viewController(for: column) as? UINavigationController
    }

    /// A reader for the thread, or nil when it is gone.
    private func reader(for id: ThreadSummary.ID) -> ThreadViewController? {
        guard let thread = try? model.database.thread(id),
            let account = model.accounts.first(where: { $0.id == id.accountID })
        else { return nil }
        let model = model
        let viewModel = ThreadViewModel(
            thread: thread,
            accountEmail: account.email,
            accountColor: account.color,
            messages: { model.database.messages(inThread: id) },
            load: { try await model.loadMessages(of: id) },
            attachmentData: { try await model.attachmentData($0, in: $1) },
            actions: actions,
            navigate: { [weak self] route in self?.handle(route) }
        )
        return ThreadViewController(
            viewModel: viewModel,
            openURL: { url in UIApplication.shared.open(url) },
            close: { [weak self] in self?.closeThread() })
    }

    /// Leaves the open thread, after an action that takes it out of the mailbox.
    private func closeThread() {
        guard let split else { return }
        shown.thread = nil
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
                threads: { model.database.threads(in: mailbox) },
                refresh: { try await model.syncAll() },
                loadOlder: { try await model.loadOlder(mailbox) },
                navigate: { [weak self] route in self?.handle(route) },
                actions: actions
            ),
            searchResults: results)
    }

    /// The one place navigation happens (ADR-011).
    func handle(_ route: Route) {
        switch route {
        case .mailbox(let mailbox):
            guard let split else { return }
            let labels = (try? model.database.labels(for: mailbox.accountID ?? AccountID(rawValue: ""))) ?? []
            let title = labels.first { $0.id == mailbox.labelID }?.name
            shown = Shown(mailbox: mailbox, title: title)
            let list = mailboxViewController(for: mailbox, title: title)
            if split.isCollapsed {
                navigation(for: .compact)?.pushViewController(list, animated: true)
            } else {
                navigation(for: .supplementary)?.setViewControllers([list], animated: false)
                navigation(for: .secondary)?.setViewControllers([NoThreadViewController()], animated: false)
                (navigation(for: .primary)?.viewControllers.first as? MailboxesViewController)?.selectedMailbox =
                    mailbox
                split.show(.supplementary)
            }
        case .thread(let id):
            guard let split, let reader = reader(for: id) else { return }
            shown.thread = id
            if split.isCollapsed {
                navigation(for: .compact)?.pushViewController(reader, animated: true)
            } else {
                navigation(for: .secondary)?.setViewControllers([reader], animated: false)
                split.show(.secondary)
            }
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
        case .settings:
            showSettings()
        case .compose(let draft):
            guard let account = model.accounts.first(where: { $0.id == draft.accountID }),
                let presenter = topViewController()
            else { return }
            let actions = actions
            let composer = ComposeViewController(
                viewModel: ComposeViewModel(
                    draft: draft, accountEmail: account.email, senders: model.accounts,
                    signature: { [database = model.database] in try? database.signature(for: $0) },
                    suggest: { [database = model.database] in (try? database.contacts(matching: $0)) ?? [] },
                    saveDraft: { actions.saveDraft($0) }, deleteDraft: { actions.deleteDraft($0) },
                    send: { actions.send($0) }))
            let navigation = UINavigationController(rootViewController: composer)
            navigation.modalPresentationStyle = .pageSheet
            presenter.present(navigation, animated: true)
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
        if !navigationController.viewControllers.contains(where: { $0 is ThreadViewController }) { shown.thread = nil }
        if navigationController.viewControllers.count == 1 { shown = Shown() }
    }
}
