import MailCore
import MailUI
import UIKit

/// The commands every window answers alike when none of its screens has them, whatever it shows: New Viewer Window,
/// New Message and Get Mail. Get Mail is the app's own sync (`AppModel.getMail`), so it outlives the window.
final class EveryWindowCommands {
    private let model: AppModel

    init(model: AppModel) {
        self.model = model
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
            return .ready(perform: { [model] in model.getMail() })
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
}
