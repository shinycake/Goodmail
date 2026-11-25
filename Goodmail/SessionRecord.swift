import Foundation
import MailCore
import UIKit

/// What a window's scene session remembers of the window it last held, for when the system discards the session and
/// the window won't come back (`AppDelegate`): neither the scene nor its delegate is there to say by then, and the
/// session's restoration activity is often missing, as for a window closed before the system saved it. Kept in the
/// session's `userInfo`, so it is only ever one of these.
enum SessionRecord: Equatable {
    /// A message window, under its ticket to the message's name (`ComposeWindowCoordinator.ticket`).
    case composing(DraftWindowTicket)
    /// A window that disconnected while the database was still opening, before it filled.
    case leftOpening

    private static let key = "com.idanbirman.goodmail.window"

    /// What `session` remembers, if anything.
    static func of(_ session: UISceneSession) -> SessionRecord? {
        guard let record = session.userInfo?[key] as? [String: String] else { return nil }
        switch record["kind"] {
        case "composing":
            guard let window = record["window"], let id = record["ticket"].flatMap(UUID.init(uuidString:)) else {
                return nil
            }
            return .composing(DraftWindowTicket(window: window, id: id))
        case "leftOpening":
            return .leftOpening
        default:
            return nil
        }
    }

    /// Makes `record` what `session` remembers, in place of anything before.
    static func set(_ record: SessionRecord, on session: UISceneSession) {
        let stored: [String: String] =
            switch record {
            case .composing(let ticket): ["kind": "composing", "window": ticket.window, "ticket": ticket.id.uuidString]
            case .leftOpening: ["kind": "leftOpening"]
            }
        session.userInfo = (session.userInfo ?? [:]).merging([key: stored]) { $1 }
    }

    /// `session` connects a window afresh: what it remembered was of one gone.
    static func clear(_ session: UISceneSession) {
        session.userInfo?[key] = nil
    }
}
