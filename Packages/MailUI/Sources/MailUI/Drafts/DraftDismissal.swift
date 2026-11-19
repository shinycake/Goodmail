import UIKit

/// What dismissing minimized messages does to them, asked each time: a card's close button in the picker asks it for
/// one, Dismiss All in the pill's menu once for all of them. Nothing is lost without this choice.
enum DraftDismissal: CaseIterable {
    /// Throws the message away, with the provider's copy.
    case delete
    /// Keeps the message in the provider's Drafts.
    case save

    func apply(to composer: ComposeViewController) {
        switch self {
        case .delete: composer.deleteDraft()
        case .save: composer.saveDraft()
        }
    }

    /// The choice's button for `count` messages.
    func title(count: Int) -> String {
        switch self {
        case .delete:
            String(
                localized: "Delete \(count) Drafts", table: "Drafts", bundle: .module,
                comment: "Discards the minimized messages; the argument is how many")
        case .save:
            String(
                localized: "Save \(count) Drafts", table: "Drafts", bundle: .module,
                comment: "Keeps the minimized messages in Drafts; the argument is how many")
        }
    }

    var style: UIAlertAction.Style {
        switch self {
        case .delete: .destructive
        case .save: .default
        }
    }
}
