import UIKit

/// A window's navigation stack, with the undo toast floating over whichever screen shows, above the toolbar.
/// Shaking undoes the last action from any screen.
public final class MailNavigationController: UINavigationController {
    private let actions: MailActions
    private let toast = UndoToastView()
    private var shownToast: MailActions.Toast.ID?
    private var toastBottom: NSLayoutConstraint!

    public init(rootViewController: UIViewController, actions: MailActions) {
        self.actions = actions
        super.init(rootViewController: rootViewController)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    public override func viewDidLoad() {
        super.viewDidLoad()
        toast.alpha = 0
        toast.onUndo = { [weak self] in self?.actions.undoLast() }
        toast.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(toast)
        toastBottom = toast.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            toastBottom,
            toast.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor),
        ])
    }

    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        placeToast()
    }

    private func placeToast() {
        view.bringSubviewToFront(toast)
        // The shown screen's safe area ends above the toolbar when there is one, else above the home indicator.
        let inset = topViewController?.view.safeAreaInsets.bottom ?? view.safeAreaInsets.bottom
        let constant = -inset - 12
        if toastBottom.constant != constant { toastBottom.constant = constant }
    }

    /// Called by UIKit whenever the observed toast changes.
    public override func updateProperties() {
        super.updateProperties()
        let current = actions.toast
        guard current?.id != shownToast else { return }
        shownToast = current?.id
        if let current {
            toast.show(current.message)
            placeToast()
            view.layoutIfNeeded()
            toast.transform = CGAffineTransform(translationX: 0, y: 20).scaledBy(x: 0.9, y: 0.9)
            UIAccessibility.post(notification: .announcement, argument: current.message)
        }
        UIView.animate(springDuration: 0.35, bounce: 0.2) {
            self.toast.alpha = current == nil ? 0 : 1
            self.toast.transform = .identity
        }
    }

    public override var canBecomeFirstResponder: Bool { true }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }

    /// Shake to undo the last action, as everywhere on iOS.
    public override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return super.motionEnded(motion, with: event) }
        actions.undoLast()
    }
}
