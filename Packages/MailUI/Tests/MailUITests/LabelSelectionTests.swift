import MailCore
import Testing

@testable import MailUI

@MainActor
struct LabelSelectionTests {
    private let labels = [
        MailLabel(id: "INBOX", name: "INBOX", kind: .system),
        MailLabel(id: "Label_1", name: "Receipts", kind: .user),
        MailLabel(id: "Label_2", name: "Travel", kind: .user),
        MailLabel(id: "Label_3", name: "Old", kind: .user, isHidden: true),
    ]

    private func thread(_ labels: Set<String>) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "\(labels.sorted())"), subject: "",
            snippet: "", sender: Contact(name: nil, address: "x@example.com"), date: .now, isUnread: false,
            messageCount: 1, labelIDs: labels)
    }

    @Test func showsVisibleUserLabelsWithTheirStateAcrossTheThreads() {
        let selection = LabelSelection(
            labels: labels, threads: [thread(["INBOX", "Label_1", "Label_2"]), thread(["Label_1"])])
        #expect(selection.choices.map(\.label.name) == ["Receipts", "Travel"])
        #expect(selection.choices.map(\.state) == [.on, .mixed])
        #expect(selection.action == nil)
    }

    @Test func onlyWhatTheUserChangedIsApplied() {
        var selection = LabelSelection(labels: labels, threads: [thread(["Label_1"]), thread([])])
        selection.toggle("Label_1")
        #expect(selection.action == .modifyLabels(add: ["Label_1"], remove: []), "mixed became on")
        selection.toggle("Label_1")
        #expect(selection.action == .modifyLabels(add: [], remove: ["Label_1"]))
        selection.toggle("Label_2")
        #expect(selection.action == .modifyLabels(add: ["Label_2"], remove: ["Label_1"]))
    }

    @Test func togglingBackToTheStartChangesNothing() {
        var selection = LabelSelection(labels: labels, threads: [thread(["Label_2"])])
        selection.toggle("Label_2")
        selection.toggle("Label_2")
        #expect(selection.action == nil)
    }
}
