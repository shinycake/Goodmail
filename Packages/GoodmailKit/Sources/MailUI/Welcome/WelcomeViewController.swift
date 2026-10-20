import UIKit

/// Shown while no account has been added.
public final class WelcomeViewController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

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
        contentUnavailableConfiguration = content
    }
}
