import Foundation
import MailCore
import Testing

@testable import GmailProvider

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The vacation responder reads and writes as an `AutoReply`.
struct GmailAutoReplyTests {
    private let keychain = InMemorySecretStore()

    private func client(_ http: FixtureHTTPClient) async throws -> GmailClient {
        let session = try await OAuthSession.signIn(
            client: .gmail, code: "4/abc", pkce: .generate(), http: http, keychain: keychain
        ).session
        return GmailClient(session: session, http: http)
    }

    private func http() -> FixtureHTTPClient {
        FixtureHTTPClient([
            "/token": [.init(fixture: "token-exchange")],
            "/gmail/v1/users/me/settings/vacation": [.init(fixture: "vacation")],
        ])
    }

    @Test func aScheduledResponderReadsWithItsTimesAndPlainText() async throws {
        let reply = try await client(http()).autoReply()
        #expect(
            reply
                == AutoReply(
                    schedule: .between(
                        DateInterval(
                            start: Date(timeIntervalSince1970: 1_800_000_000),
                            end: Date(timeIntervalSince1970: 1_800_086_400))),
                    subject: "Away", message: "Back on Monday", contactsOnly: true))
    }

    @Test(arguments: [
        (GmailVacation.from(enable: false, start: "1", end: "2"), AutoReply.Schedule.off),
        (GmailVacation.from(enable: true, start: nil, end: nil), .on),
        (GmailVacation.from(enable: true, start: "1800000000000", end: nil), .on),
    ])
    func theScheduleFollowsTheTimesGiven(vacation: GmailVacation, schedule: AutoReply.Schedule) {
        #expect(vacation.autoReply.schedule == schedule)
    }

    @Test func savingPutsTheWholeResponder() async throws {
        let http = http()
        let interval = DateInterval(start: Date(timeIntervalSince1970: 1_800_000_000), duration: 3600)
        try await client(http).setAutoReply(
            AutoReply(schedule: .between(interval), subject: "Away", message: "Back soon", contactsOnly: false))

        let put = try #require(http.requests.last)
        #expect(put.httpMethod == "PUT")
        let sent = try JSONDecoder().decode(GmailVacation.self, from: put.httpBody ?? Data())
        #expect(sent.enableAutoReply == true)
        #expect(sent.responseSubject == "Away")
        #expect(sent.responseBodyPlainText == "Back soon")
        #expect(sent.restrictToContacts == false)
        #expect(sent.startTime == "1800000000000")
        #expect(sent.endTime == "1800003600000")
    }

    @Test func turningItOffSendsNoTimes() throws {
        let vacation = GmailVacation(AutoReply(schedule: .off, message: "Back soon"))
        #expect(vacation.enableAutoReply == false)
        #expect(vacation.startTime == nil && vacation.endTime == nil)
    }
}

extension GmailVacation {
    fileprivate static func from(enable: Bool, start: String?, end: String?) -> GmailVacation {
        var vacation = GmailVacation(AutoReply())
        vacation.enableAutoReply = enable
        vacation.startTime = start
        vacation.endTime = end
        return vacation
    }
}
