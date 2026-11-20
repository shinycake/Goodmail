import Foundation
import MailCore

extension MailActions {
    /// Gives threads a label and leaves them where they are, called `name` in the toast, which undoes it.
    func addLabel(_ labelID: String, named name: String, to threads: [ThreadSummary.ID]) {
        feedback(.change)
        apply(
            confirmation: String(
                localized: "\(threads.count) labeled \(name)", table: "Actions", bundle: .module,
                comment: "Toast after giving threads a label; the second value is the label's name")
        ) { try await $0.perform(.modifyLabels(add: [labelID], remove: []), on: threads) }
    }
}
