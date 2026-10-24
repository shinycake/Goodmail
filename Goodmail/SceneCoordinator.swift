import MailCore
import MailStore
import MailUI
import UIKit

/// One per window (ADR-011): decides what the window shows and owns the flows that change it.
final class SceneCoordinator {
    private let window: UIWindow
    private let model: AppModel
    private let actions: MailActions
    private var failures: Task<Void, Never>?
    /// Failed sends already shown, so each is offered once per launch.
    private var shownFailures: Set<Draft.ID> = []

    init(window: UIWindow, model: AppModel) {
        self.window = window
        self.model = model
        actions = MailActions(commands: model.commands)
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
            retry: { try? commands.retrySend(message.draft) },
            delete: { try? commands.discardSend(message.id) })
        presenter.present(alert, animated: true)
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

    private func showMailbox() {
        let model = model
        let viewModel = MailboxViewModel(
            accounts: model.accounts,
            threads: { model.database.threads(labeled: "INBOX") },
            refresh: { try await model.syncAll() },
            loadOlder: { try await model.loadOlder(label: "INBOX") },
            navigate: { [weak self] route in self?.handle(route) },
            actions: actions
        )
        let mailbox = MailNavigationController(
            rootViewController: MailboxViewController(viewModel: viewModel), actions: actions)
        if window.rootViewController == nil {
            window.rootViewController = mailbox
        } else {
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                self.window.rootViewController = mailbox
            }
        }
    }

    /// The one place navigation happens (ADR-011).
    func handle(_ route: Route) {
        switch route {
        case .thread(let id):
            guard let thread = try? model.database.thread(id),
                let account = model.accounts.first(where: { $0.id == id.accountID }),
                let navigation = window.rootViewController as? UINavigationController
            else { return }
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
            let reader = ThreadViewController(
                viewModel: viewModel,
                openURL: { url in UIApplication.shared.open(url) },
                close: { [weak navigation] in navigation?.popViewController(animated: true) })
            navigation.pushViewController(reader, animated: true)
        case .compose(let draft):
            guard let account = model.accounts.first(where: { $0.id == draft.accountID }),
                let presenter = topViewController()
            else { return }
            let actions = actions
            let composer = ComposeViewController(
                viewModel: ComposeViewModel(draft: draft, accountEmail: account.email) { actions.send($0) })
            let navigation = UINavigationController(rootViewController: composer)
            navigation.modalPresentationStyle = .pageSheet
            presenter.present(navigation, animated: true)
        }
    }
}
