import Foundation
import MailCore
import Testing

struct TransferTests {
    private let invitation = TransferInvitation(
        service: "Goodmail-abc", senderKey: Data(repeating: 7, count: 32), secret: Data(repeating: 9, count: 32))

    @Test func theCodeReadsBackAsTheInvitation() throws {
        let url = invitation.url
        #expect(url.scheme == "goodmail-transfer")
        #expect(TransferInvitation(url: url) == invitation)
    }

    @Test(arguments: [
        "https://example.com/?s=a&k=b&c=d",
        "goodmail-transfer://2?s=Goodmail-abc&k=BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc&c=CQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQk",
        "goodmail-transfer://1?s=Goodmail-abc&k=short&c=CQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQk",
        "goodmail-transfer://1?k=BwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwcHBwc&c=CQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQkJCQk",
    ])
    func anythingElseIsntAnInvitation(_ text: String) throws {
        #expect(TransferInvitation(url: try #require(URL(string: text))) == nil)
    }

    @Test func onlyAccountsNotHereAlreadyAreNewByIDOrAddress() {
        func entry(_ id: String, _ email: String, _ service: MailService) -> TransferPayload.Entry {
            let account = Account(id: AccountID(rawValue: id), email: email, color: .blue, service: service)
            return .init(id: account.id, profile: .init(account, position: 0), signIn: Data())
        }
        let here = [
            Account(id: AccountID(rawValue: "g"), email: "me@gmail.com", color: .blue, service: .gmail),
            Account(id: AccountID(rawValue: "x"), email: "Me@Outlook.com", color: .blue, service: .outlook),
        ]
        let sameID = entry("g", "other@gmail.com", .gmail)
        let sameAddress = entry("o", "me@outlook.com", .outlook)
        let sameAddressElsewhere = entry("i", "me@outlook.com", .imap)
        let new = entry("c", "me@icloud.com", .icloud)
        let payload = TransferPayload(entries: [sameID, sameAddress, sameAddressElsewhere, new])

        #expect(payload.entries(newTo: here) == [sameAddressElsewhere, new])
    }
}
