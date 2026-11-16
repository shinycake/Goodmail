import MailCore
import Testing

struct AccountOfferTests {
    private let gmail = Account(id: AccountID(rawValue: "g"), email: "me@gmail.com", color: .blue, service: .gmail)
    private let icloud = Account(id: AccountID(rawValue: "i"), email: "me@icloud.com", color: .green, service: .icloud)
    private let outlook = Account(
        id: AccountID(rawValue: "o"), email: "me@outlook.com", color: .orange, service: .outlook)

    @Test func aReinstallOffersItsOwnAccountsFirstWithTheOtherDevicesAfter() {
        let offer = AccountOffer(restorable: [gmail, icloud], elsewhere: [icloud, outlook], declined: [])

        #expect(offer == AccountOffer(accounts: [gmail, icloud, outlook], origin: .thisDevice))
    }

    @Test func aNewDeviceOffersTheOtherDevicesAccounts() {
        let offer = AccountOffer(restorable: [], elsewhere: [outlook], declined: [])

        #expect(offer == AccountOffer(accounts: [outlook], origin: .otherDevices))
    }

    @Test func turnedDownAccountsAreLeftOutAndNothingLeftIsNoOffer() {
        #expect(
            AccountOffer(restorable: [gmail], elsewhere: [outlook], declined: [gmail.id])
                == AccountOffer(accounts: [outlook], origin: .otherDevices))
        #expect(AccountOffer(restorable: [gmail], elsewhere: [], declined: [gmail.id]) == nil)
        #expect(AccountOffer(restorable: [], elsewhere: [], declined: []) == nil)
    }
}
