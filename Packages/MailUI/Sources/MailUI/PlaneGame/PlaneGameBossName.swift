import Foundation
import PlaneGame

/// What each boss is called, for its title as it arrives and for VoiceOver.
nonisolated enum PlaneGameBossName {
    static func of(_ kind: PlaneGameBoss.Kind) -> String {
        switch kind {
        case .junk:
            String(
                localized: "Junk Mail", table: "PlaneGame", bundle: .module,
                comment: "A boss in the paper plane game: a spam envelope wearing a crown")
        case .phisher:
            String(
                localized: "The Phisher", table: "PlaneGame", bundle: .module,
                comment: "A boss in the paper plane game: an at sign that casts hooks")
        case .storm:
            String(
                localized: "Reply-All Storm", table: "PlaneGame", bundle: .module,
                comment: "A boss in the paper plane game: an envelope that fires volleys of replies")
        case .outOfOffice:
            String(
                localized: "Out of Office", table: "PlaneGame", bundle: .module,
                comment: "A boss in the paper plane game: an envelope that sends your shots back while its sign is up")
        case .mailingList:
            String(
                localized: "The Mailing List", table: "PlaneGame", bundle: .module,
                comment: "A boss in the paper plane game: an envelope that clones itself")
        case .overload:
            String(
                localized: "Inbox Overload", table: "PlaneGame", bundle: .module,
                comment: "A boss in the paper plane game: an overflowing inbox tray")
        }
    }
}
