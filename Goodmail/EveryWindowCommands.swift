import MailCore
import MailUI
import UIKit

/// The commands every window answers alike when none of its screens has them, whatever it shows: New Viewer Window,
/// New Message and Get Mail. Each window owns one, and with it the sync Get Mail starts, which ends with the window.
final class EveryWindowCommands {
    private let model: AppModel
    /// The sync Get Mail started, which another Get Mail joins rather than starting a second. Only `getMail()` changes
    /// it.
    private var syncing: Task<Void, Never>?

    init(model: AppModel) {
        self.model = model
    }

    isolated deinit {
        syncing?.cancel()
    }

    /// What `command` does from the window on `scene`. `newMessage` starts a message from that window, `nil` where it
    /// can't start one.
    func answer(to command: MailCommand, in scene: UIWindowScene?, newMessage: (() -> Void)?) -> CommandAnswer {
        switch command {
        case .newWindow:
            return Self.newViewerWindow(beside: scene)
        case .newMessage:
            guard let newMessage else { return .unavailable }
            return .ready(perform: newMessage)
        case .getMail:
            guard !model.accounts.isEmpty else { return .unavailable }
            return .ready(perform: { [weak self] in self?.getMail() })
        default:
            return .notHere
        }
    }

    /// New Viewer Window, opening beside `scene`. With no window open, the app answers it (`AppDelegate+Commands`).
    private static func newViewerWindow(beside scene: UIWindowScene?) -> CommandAnswer {
        guard UIApplication.shared.supportsMultipleScenes else { return .unavailable }
        return .ready(perform: { SceneCoordinator.openWindow(for: WindowState().activity, beside: scene) {} })
    }

    /// New Message from a window without the mail screens, as a message or Settings window on the Mac: the front mail
    /// window starts it, from its account, in a window of its own. `nil` with no mail window that can start one, or
    /// where a new message opens in a mail window's sheet, which may be behind.
    static func newMessageFromMail(placement: ComposePlacement) -> (() -> Void)? {
        guard case .ownWindow = placement,
            let mail = MailWindows.frontFirst.first(where: { $0.composingAccount != nil })
        else { return nil }
        return { [weak mail] in
            guard let mail, let account = mail.composingAccount else { return }
            mail.compose(Draft(accountID: account))
        }
    }

    /// Syncs every account now, as pull to refresh does; a failure shows on the health board.
    private func getMail() {
        guard syncing == nil else { return }
        syncing = Task { [weak self, model] in
            try? await model.syncAll()
            self?.syncing = nil
        }
    }
}
