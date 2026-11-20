import Foundation
import MailUI

extension SharedItems.Request {
    /// The parts of the Share extension's items.
    init(_ items: [NSExtensionItem]) {
        self.init(
            title: items.lazy.compactMap { $0.attributedTitle?.string }.first { !$0.isEmpty },
            texts: items.compactMap { $0.attributedContentText?.string },
            providers: items.flatMap { $0.attachments ?? [] })
    }
}
