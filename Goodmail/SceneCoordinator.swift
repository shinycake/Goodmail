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
            showMailbox(refreshing: true)
        }
    }

    private func showWelcome() {
        let welcome = WelcomeViewController { [weak self] in
            guard let self else { return }
            if try await model.addGmailAccount(using: WebAuthentication(window: window)) {
                showMailbox(refreshing: false)
            }
        }
        window.rootViewController = UINavigationController(rootViewController: welcome)
    }

    private func showMailbox(refreshing: Bool) {
        let model = model
        let viewModel = MailboxViewModel(
            accounts: model.accounts,
            threads: { model.database.threads(labeled: "INBOX") },
            refresh: { try await model.refreshInbox() }
        )
        let mailbox = UINavigationController(rootViewController: MailboxViewController(viewModel: viewModel))
        if window.rootViewController == nil {
            window.rootViewController = mailbox
        } else {
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                self.window.rootViewController = mailbox
            }
        }
        if refreshing {
            Task { await viewModel.refresh() }
        }
    }
}
