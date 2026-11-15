import Foundation
import Testing

@testable import MailCore

struct SenderDomainTests {
    @Test(arguments: [
        ("service@paypal.com", "paypal.com", "paypal.com"),
        ("noreply@Mail.GitHub.com", "mail.github.com", "github.com"),
        ("billing@shop.example.co.il", "shop.example.co.il", "example.co.il"),
    ])
    func aSenderBelongsToItsHostAndOrganization(address: String, host: String, organization: String) throws {
        let domain = try #require(SenderDomain(address: address))
        #expect(domain.host == host)
        #expect(domain.organization == organization)
    }

    @Test(arguments: ["someone@gmail.com", "friend@walla.co.il", "broken", "x@localhost", "x@exa mple.com", "x@a..com"])
    func publicMailAndMalformedAddressesHaveNoBrand(address: String) {
        #expect(SenderDomain(address: address) == nil)
    }

    @Test func bimiIsLookedUpAtTheHostThenTheOrganization() throws {
        #expect(
            try #require(SenderDomain(address: "a@mail.paypal.com")).bimiRecordNames == [
                "default._bimi.mail.paypal.com", "default._bimi.paypal.com",
            ])
        #expect(try #require(SenderDomain(address: "a@paypal.com")).bimiRecordNames == ["default._bimi.paypal.com"])
    }
}

struct BIMIRecordTests {
    @Test func theLogoComesFromTheBIMIRecordAmongOtherTXTRecords() {
        let record = BIMIRecord(txtRecords: [
            "google-site-verification=abc",
            "v=BIMI1; l=https://www.paypalobjects.com/marketing/web/logos/paypal_ppe.svg; a=https://x/y.pem",
        ])
        #expect(record?.logo == URL(string: "https://www.paypalobjects.com/marketing/web/logos/paypal_ppe.svg"))
        #expect(BIMIRecord(txtRecords: ["v=BIMI1;l=https://a.example/logo.svg;a=;"])?.logo != nil)
    }

    @Test(arguments: ["v=BIMI1; l=; a=;", "v=BIMI1; l=http://a.example/logo.svg"])
    func aDeclinedOrInsecureLogoIsNone(record: String) throws {
        #expect(try #require(BIMIRecord(txtRecords: [record])).logo == nil)
    }

    @Test func noRecordOrTwoRecordsIsNoBIMI() {
        #expect(BIMIRecord(txtRecords: []) == nil)
        #expect(BIMIRecord(txtRecords: ["l=https://a.example/logo.svg; v=BIMI1"]) == nil)
        #expect(BIMIRecord(txtRecords: ["v=BIMI1; l=https://a/1.svg", "v=BIMI1; l=https://a/2.svg"]) == nil)
    }

    @Test func txtRecordDataJoinsItsStrings() {
        #expect(BIMIRecord.text(ofTXTRecordData: [3] + Array("v=B".utf8) + [4] + Array("IMI1".utf8)) == "v=BIMI1")
        #expect(BIMIRecord.text(ofTXTRecordData: [5, 65]) == nil)
    }
}
