import UIKit

/// A date and time to send a message at, from a minute from now on.
final class SendLaterPickerViewController: UIViewController {
    private let picker = UIDatePicker()
    private let schedule: (Date) -> Void

    init(schedule: @escaping (Date) -> Void) {
        self.schedule = schedule
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Send Later", bundle: .module, comment: "Menu of times to send a message")
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
        picker.date = SendLaterChoice.choices(at: .now).first?.date ?? .now.addingTimeInterval(3600)
        picker.accessibilityIdentifier = "sendLater.picker"
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
            title: String(localized: "Schedule", bundle: .module, comment: "Schedules the message for the picked time"),
            primaryAction: UIAction { [weak self] _ in
                guard let self else { return }
                // The sheet may have stayed open past the earliest time it allowed.
                schedule(max(picker.date, .now.addingTimeInterval(60)))
            })
        done.style = .prominent
        navigationItem.rightBarButtonItem = done
    }
}
