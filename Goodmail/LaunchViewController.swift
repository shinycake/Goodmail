import UIKit

/// What a window shows before the mail screens can: nothing while the database opens, which is quick, or why the mail
/// can't be shown when it couldn't open.
final class LaunchViewController: UIViewController {
    private let failure: (any Error)?

    /// `failure` is why the database couldn't open; without one, the window is blank until it has.
    init(failure: (any Error)? = nil) {
        self.failure = failure
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        guard let failure else { return }
        var content = UIContentUnavailableConfiguration.empty()
        content.image = UIImage(systemName: "exclamationmark.triangle")
        content.text = String(
            localized: "Can’t Open Your Mail", comment: "Title shown instead of the mail when its database can't open")
        let explanation = String(
            localized: "Make sure there’s free space on this device, then open Goodmail again.",
            comment: "Shown instead of the mail when its database can't open")
        // The error is for a report; the reader acts on the sentence above it.
        content.secondaryText = "\(explanation)\n\n\(failure.localizedDescription)"
        contentUnavailableConfiguration = content
    }
}
