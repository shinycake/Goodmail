import MailCore
import UIKit

/// The taps the reader feels for what they do, one for each kind of action, so the same kind always feels the same
/// (HIG, Playing haptics). Kept few and light: a tap confirms an action, it doesn't decorate one.
enum Haptic: Equatable {
    /// The thread left the list: archived, trashed, moved, snoozed, muted or reported as spam. A soft thud, as of
    /// something dropping into a box.
    case putAway
    /// The thread changed in place: starred, read, labeled or brought back.
    case change
    /// Gone for good. Firmer than putting away, because nothing undoes it.
    case deleteForever
    /// A message was sent or scheduled.
    case sent
    /// The last action was taken back.
    case undone

    /// The tap for taking `action` on threads.
    static func performing(_ action: ThreadAction) -> Haptic {
        switch action {
        case .deleteForever: .deleteForever
        case .trash: .putAway
        case .untrash: .change
        case .modifyLabels(_, let remove): remove.contains(SystemLabel.inbox) ? .putAway : .change
        }
    }
}

/// Plays haptics through UIKit's feedback generators attached to a view, which play only while the view is in a
/// window and stay silent when System Haptics is off in Settings, or on a device without a Taptic Engine.
final class HapticPlayer {
    private let soft: UIImpactFeedbackGenerator
    private let light: UIImpactFeedbackGenerator
    private let rigid: UIImpactFeedbackGenerator
    private let notification: UINotificationFeedbackGenerator

    init(view: UIView) {
        soft = UIImpactFeedbackGenerator(style: .soft, view: view)
        light = UIImpactFeedbackGenerator(style: .light, view: view)
        rigid = UIImpactFeedbackGenerator(style: .rigid, view: view)
        notification = UINotificationFeedbackGenerator(view: view)
    }

    func play(_ haptic: Haptic) {
        switch haptic {
        case .putAway: soft.impactOccurred()
        case .change, .undone: light.impactOccurred(intensity: 0.7)
        case .deleteForever: rigid.impactOccurred()
        case .sent: notification.notificationOccurred(.success)
        }
    }
}
