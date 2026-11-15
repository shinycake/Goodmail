import MailCore
import Testing

struct SendingAddressTests {
    private let workAlias = Contact(name: "Dana at Work", address: "dana@work.example")
    private var personal: Account {
        Account(
            id: AccountID(rawValue: "p"), email: "me@example.com", color: .blue, service: .gmail, aliases: [workAlias])
    }
    private let icloud = Account(id: AccountID(rawValue: "i"), email: "me@icloud.com", color: .green, service: .icloud)

    @Test func newMailCanGoFromEveryAccountAndAlias() {
        let choices = SendingAddress.choices(for: Draft(accountID: personal.id), among: [personal, icloud])
        #expect(choices.map(\.email) == ["me@example.com", "dana@work.example", "me@icloud.com"])
        #expect(choices[1] == SendingAddress(account: personal, alias: workAlias))
    }

    @Test(
        "A reply or saved draft picks only among its own account's addresses",
        arguments: [
            Draft(accountID: AccountID(rawValue: "p"), threadID: "t1"),
            Draft(
                accountID: AccountID(rawValue: "p"),
                savedDraft: Message.ID(accountID: AccountID(rawValue: "p"), messageID: "d")),
        ])
    func answersStayInTheirAccount(draft: Draft) {
        #expect(
            SendingAddress.choices(for: draft, among: [personal, icloud]).map(\.email)
                == ["me@example.com", "dana@work.example"])
    }
}
