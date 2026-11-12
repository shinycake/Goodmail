import Foundation

/// One of the tabs Gmail sorts the Inbox into. A thread with no category label is Primary, as in Gmail.
public enum InboxCategory: String, CaseIterable, Codable, Sendable {
    case primary, promotions, social, updates, forums

    /// Gmail's system label for the category.
    public var labelID: String {
        switch self {
        case .primary: "CATEGORY_PERSONAL"
        case .promotions: "CATEGORY_PROMOTIONS"
        case .social: "CATEGORY_SOCIAL"
        case .updates: "CATEGORY_UPDATES"
        case .forums: "CATEGORY_FORUMS"
        }
    }

}
