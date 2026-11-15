import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
struct LabelEditingTests {
    private let gmail = Account(id: AccountID(rawValue: "g"), email: "g@example.com", color: .teal, service: .gmail)
    private let icloud = Account(id: AccountID(rawValue: "i"), email: "i@icloud.com", color: .blue, service: .icloud)

    private static let editor = LabelEditor(
        deletion: .keepsMail, create: { MailLabel(id: "Label_9", name: $0, kind: .user) }, rename: { _, _ in },
        delete: { _ in })

    @Test(arguments: [
        ("Receipts", "Receipts"), ("  Receipts  ", "Receipts"), ("Projects / Goodmail", "Projects/Goodmail"),
        ("קבלות/2026", "קבלות/2026"),
    ])
    func aNameLosesTheSpacesAroundItsSteps(_ typed: String, _ name: String) {
        #expect(LabelName.normalized(typed) == name)
    }

    @Test(arguments: [nil, "", "   ", "Projects//Goodmail", "/Projects", "Projects/"])
    func aNameWithABlankStepNamesNothing(_ typed: String?) {
        #expect(LabelName.normalized(typed) == nil)
    }

    @Test func aLabelMadeInThePickerIsListedLastAndApplied() {
        var selection = LabelSelection(
            labels: [MailLabel(id: "Label_1", name: "Receipts", kind: .user)], threads: [])
        selection.add(MailLabel(id: "Label_9", name: "Travel", kind: .user))
        selection.add(MailLabel(id: "Label_9", name: "Travel", kind: .user))

        #expect(selection.choices.map(\.label.name) == ["Receipts", "Travel"], "once")
        #expect(selection.choices.last?.state == .on)
        #expect(selection.action == .modifyLabels(add: ["Label_9"], remove: []))
    }

    @Test func moveOffersANewLabelOnlyForOneAccount() {
        let one = MoveViewModel(
            threads: [ThreadSummary.ID(accountID: gmail.id, threadID: "t")], from: .inbox, labels: { _ in [] },
            editor: { _ in Self.editor }, actions: nil)
        #expect(one.editor != nil)

        let several = MoveViewModel(
            threads: [
                ThreadSummary.ID(accountID: gmail.id, threadID: "t"),
                ThreadSummary.ID(accountID: icloud.id, threadID: "u"),
            ], from: .inbox, labels: { _ in [] }, editor: { _ in Self.editor }, actions: nil)
        #expect(several.editor == nil, "each account has its own labels")
    }

    @Test func onlyUserLabelRowsCanBeEditedAndNewLabelListsTheAccountsThatCan() async {
        let receipts = Mailbox(labelID: "Label_1", accountID: gmail.id)
        let directory = MailboxDirectory(labels: [
            MailboxDirectory.Label(mailbox: receipts, name: "Receipts", color: nil)
        ])
        let viewModel = MailboxesViewModel(
            accounts: [gmail, icloud],
            directory: {
                AsyncThrowingStream {
                    $0.yield(directory)
                    $0.finish()
                }
            },
            labelEditor: { [gmail] in $0 == gmail.id ? Self.editor : nil })
        await viewModel.observe()

        #expect(viewModel.label(at: .mailbox(receipts))?.name == "Receipts")
        #expect(viewModel.label(at: .mailbox(.inbox)) == nil)
        #expect(viewModel.label(at: .mailbox(Mailbox(labelID: SystemLabel.inbox, accountID: gmail.id))) == nil)
        #expect(viewModel.label(at: .snoozed) == nil)
        #expect(viewModel.labelAccounts == [gmail])
    }

    @Test func deletingALabelCountsTheAccountsLabelsNestedInIt() async {
        func label(_ id: String, _ name: String, _ account: Account) -> MailboxDirectory.Label {
            MailboxDirectory.Label(mailbox: Mailbox(labelID: id, accountID: account.id), name: name, color: nil)
        }
        let projects = label("Label_1", "Projects", gmail)
        let directory = MailboxDirectory(labels: [
            projects, label("Label_2", "Projects/Goodmail", gmail), label("Label_3", "Projects/Goodmail/Design", gmail),
            label("Label_4", "Projects archive", gmail), label("Projects/Other", "Projects/Other", icloud),
        ])
        let viewModel = MailboxesViewModel(
            accounts: [gmail, icloud],
            directory: {
                AsyncThrowingStream {
                    $0.yield(directory)
                    $0.finish()
                }
            })
        await viewModel.observe()

        #expect(
            viewModel.nestedLabelCount(in: projects) == 2, "not a name that only starts the same, nor another account's"
        )
        #expect(viewModel.nestedLabelCount(in: directory.labels[2]) == 0)
        #expect(LabelDeletion.keepsMail.message(nested: 0) == LabelDeletion.keepsMail.consequence)
        #expect(LabelDeletion.keepsMail.message(nested: 2).hasSuffix(LabelDeletion.keepsMail.consequence))
        #expect(LabelDeletion.keepsMail.message(nested: 2).contains("2"))
    }

    @Test func theDeleteConfirmationSaysWhatHappensToTheMail() {
        #expect(MailService.gmail.labelDeletion == .keepsMail)
        #expect(MailService.outlook.labelDeletion == .movesMailToTrash)
        #expect(MailService.icloud.labelDeletion == .deletesMail)
        #expect(MailService.imap.labelDeletion == .deletesMail)
        #expect(Set([LabelDeletion.keepsMail, .movesMailToTrash, .deletesMail].map(\.consequence)).count == 3)
    }
}
