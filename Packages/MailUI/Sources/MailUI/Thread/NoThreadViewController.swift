import UIKit

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
}
