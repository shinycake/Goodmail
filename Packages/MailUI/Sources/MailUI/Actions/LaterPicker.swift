import UIKit

/// A date and time for later, from a minute from now on: to send a message at or to snooze a thread until.
final class LaterPickerViewController: UIViewController {
    private let picker = UIDatePicker()
    private let initial: Date
    private let actionTitle: String
    private let pick: (Date) -> Void

    init(title: String, actionTitle: String, initial: Date?, pick: @escaping (Date) -> Void) {
        self.initial = initial ?? .now.addingTimeInterval(3600)
        self.actionTitle = actionTitle
        self.pick = pick
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    /// Presents a picker from `presenter`, which it dismisses before handing over the date.
    static func present(
        from presenter: UIViewController, title: String, actionTitle: String, initial: Date?,
        pick: @escaping (Date) -> Void
    ) {
        let picker = LaterPickerViewController(title: title, actionTitle: actionTitle, initial: initial) {
            [weak presenter] date in
            presenter?.dismiss(animated: true) { pick(date) }
        }
        let navigation = UINavigationController(rootViewController: picker)
        navigation.sheetPresentationController?.detents = [.medium(), .large()]
        presenter.present(navigation, animated: true)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        picker.datePickerMode = .dateAndTime
        picker.preferredDatePickerStyle = .inline
        picker.minuteInterval = 5
        picker.minimumDate = .now.addingTimeInterval(60)
        picker.date = initial
        picker.accessibilityIdentifier = "later.picker"
        picker.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(picker)
        NSLayoutConstraint.activate([
            picker.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            picker.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            picker.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            systemItem: .cancel, primaryAction: UIAction { [weak self] _ in self?.dismiss(animated: true) })
        let done = UIBarButtonItem(
            title: actionTitle,
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                // The sheet may have stayed open past the earliest time it allowed.
                pick(max(picker.date, .now.addingTimeInterval(60)))
            })
        done.style = .prominent
        navigationItem.rightBarButtonItem = done
    }
}
