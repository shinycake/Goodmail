import Testing

@testable import MailCore

struct AlertReceiptTests {
    @Test func theAlertsIDIsReadAsTheRelayWroteIt() {
        let payload: [AnyHashable: Any] = ["alert": "1B4E28BA-2FA1-11D2-883F-0016D3CCA427", "account": "a"]
        #expect(AlertReceipt.id(in: payload) == "1b4e28ba-2fa1-11d2-883f-0016d3cca427")
    }

    @Test func aPushWithoutAnIDHasNothingToConfirm() {
        #expect(AlertReceipt.id(in: [:]) == nil)
        #expect(AlertReceipt.id(in: ["alert": "not-an-id"]) == nil)
        #expect(AlertReceipt.id(in: ["alert": ["title": "Dana"]]) == nil)
    }
}
