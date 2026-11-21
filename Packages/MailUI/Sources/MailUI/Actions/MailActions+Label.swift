import Foundation
import MailCore

extension MailActions {
    /// Gives threads a label and leaves them where they are, called `name` in the toast, which undoes it.
    func addLabel(_ labelID: String, named name: String, to threads: [ThreadSummary.ID]) {
        let action = ThreadAction.modifyLabels(add: [labelID], remove: [])
        let change = MailChange(.action(action), on: threads)
        changed?(change)
        feedback(.change)
        apply(
            change,
            confirmation: String(
                localized: "\(threads.count) labeled \(name)", table: "Actions", bundle: .module,
                comment: "Toast after giving threads a label; the second value is the label's name")
        ) { try await $0.perform(action, on: threads) }
    }

}
