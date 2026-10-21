import MailCore
import MailStore
import MailUI
import UIKit

/// One per window (ADR-011): decides what the window shows and owns the flows that change it.
final class SceneCoordinator {
    private let window: UIWindow
    private let model: AppModel

    init(window: UIWindow, model: AppModel) {
        self.window = window
        self.model = model
    }

    func start() {
        if model.accounts.isEmpty {
            showWelcome()
        } else {
            showMailbox()
        }
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
            navigate: { [weak self] route in self?.handle(route) }
        )
        let mailbox = UINavigationController(rootViewController: MailboxViewController(viewModel: viewModel))
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
                attachmentData: { try await model.attachmentData($0, in: $1) }
            )
            let reader = ThreadViewController(viewModel: viewModel) { url in UIApplication.shared.open(url) }
            navigation.pushViewController(reader, animated: true)
        }
    }
}
