import Foundation
import MailCore

/// The After Archive or Delete choices, as Settings names them.
extension AfterRemoval {
    var title: String {
        switch self {
        case .next:
            String(
                localized: "Show Next Conversation", table: "Settings", bundle: .module,
                comment: "After Archive or Delete choice: the conversation below opens")
        case .list:
            String(
                localized: "Return to the List", table: "Settings", bundle: .module,
                comment: "After Archive or Delete choice: back to the list, with nothing open")
        }
    }
}
