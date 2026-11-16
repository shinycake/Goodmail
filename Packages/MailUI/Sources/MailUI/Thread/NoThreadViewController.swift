public import UIKit

/// What the message column shows beside a list while no thread is open.
public final class NoThreadViewController: UIViewController {
    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        var empty = UIContentUnavailableConfiguration.empty()
        empty.image = UIImage(systemName: "envelope")
        empty.text = String(
            localized: "No Message Selected", table: "Thread", bundle: .module,
            comment: "Shown beside the list on iPad while no thread is open")
        contentUnavailableConfiguration = empty
    }

    /// Nothing to act on, so no toolbar: each screen of a stack sets its own as it appears.
    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setToolbarHidden(true, animated: animated)
    }
}
