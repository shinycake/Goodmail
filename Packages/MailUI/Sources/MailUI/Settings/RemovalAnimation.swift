import Foundation

/// How a thread leaves the list when it is trashed, archived or deleted forever: into a box whose lid opens for it
/// and dissolving into dust, or with the list's own standard removal.
public enum RemovalAnimation: String, CaseIterable, Sendable {
    case playful
    case subtle

    var title: String {
        switch self {
        case .playful:
            String(
                localized: "Playful", table: "Settings", bundle: .module,
                comment: "Removal animation: rows go into a trash can or archive box, or dissolve")
        case .subtle:
            String(
                localized: "Subtle", table: "Settings", bundle: .module,
                comment: "Removal animation: rows slide away with the standard animation")
        }
    }

    /// Whether removals get the box and dissolve animations. Reduce Motion always gets the subtle ones.
    func plays(reducingMotion: Bool) -> Bool {
        switch self {
        case .playful: !reducingMotion
        case .subtle: false
        }
    }
}
