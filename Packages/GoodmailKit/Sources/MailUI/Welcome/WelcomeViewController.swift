import UIKit

/// Shown while no account has been added.
public final class WelcomeViewController: UIViewController {
    private let addAccount: () async throws -> Void
    private var isAdding = false {
        didSet { setNeedsUpdateContentUnavailableConfiguration() }
    }

    /// `addAccount` returns normally when the user cancels; it throws only for real failures.
    public init(addAccount: @escaping () async throws -> Void) {
        self.addAccount = addAccount
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    public override func updateContentUnavailableConfiguration(using state: UIContentUnavailableConfigurationState) {
        guard !isAdding else {
            contentUnavailableConfiguration = UIContentUnavailableConfiguration.loading()
            return
        }
        var content = UIContentUnavailableConfiguration.empty()
        content.image = UIImage(systemName: "envelope")
        content.text = String(
            localized: "No Accounts",
            bundle: .module,
            comment: "Empty-state title shown before any mail account is added"
        )
        content.textProperties.font = Typography.title
        content.secondaryText = String(
            localized: "Add a Gmail account to get started.",
            bundle: .module,
            comment: "Empty-state explanation shown before any mail account is added"
        )
        var button = UIButton.Configuration.prominentGlass()
        button.title = String(localized: "Add Gmail Account", bundle: .module, comment: "Button that starts sign-in")
        content.button = button
        content.buttonProperties.primaryAction = UIAction { [weak self] _ in self?.startAdding() }
        contentUnavailableConfiguration = content
    }

    private func startAdding() {
        guard !isAdding else { return }
        isAdding = true
        Task {
            defer { isAdding = false }
            do {
                try await addAccount()
            } catch {
                presentFailure(error)
            }
        }
    }

    private func presentFailure(_ error: any Error) {
        let alert = UIAlertController(
            title: String(localized: "Couldn’t Add Account", bundle: .module, comment: "Sign-in failure alert title"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(
            UIAlertAction(title: String(localized: "OK", bundle: .module, comment: "Dismiss"), style: .default))
        present(alert, animated: true)
    }
}
