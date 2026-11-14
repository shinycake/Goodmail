import Foundation
import MailCore
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Failures are told to the reader by what they mean, not by the error's type and number.
struct FailureReasonTests {
    /// What adding an Outlook account showed while an idle iCloud connection had been dropped.
    @Test func aDroppedSocketIsALostConnection() {
        #expect(FailureReason(NSError(domain: "Network.NWError", code: 57)) == .connectionLost)
    }

    @Test(arguments: [
        (URLError(.notConnectedToInternet), FailureReason.offline),
        (URLError(.networkConnectionLost), .connectionLost),
        (URLError(.timedOut), .timedOut),
        (URLError(.cannotFindHost), .serverUnreachable),
        (URLError(.serverCertificateUntrusted), .insecure),
        (URLError(.badServerResponse), .unknown),
    ])
    func urlErrors(error: URLError, reason: FailureReason) {
        #expect(FailureReason(error) == reason)
    }

    @Test(arguments: [
        (NSError(domain: "Network.NWError", code: 50), FailureReason.offline),
        (NSError(domain: "Network.NWError", code: 60), .timedOut),
        (NSError(domain: "Network.NWError", code: 61), .serverUnreachable),
        (NSError(domain: "Network.NWError", code: -65_554), .serverUnreachable),
        (NSError(domain: "Network.NWError", code: -9_808), .insecure),
        (NSError(domain: NSPOSIXErrorDomain, code: 54), .connectionLost),
        (NSError(domain: "Network.NWError", code: 2), .unknown),
    ])
    func socketErrors(error: NSError, reason: FailureReason) {
        #expect(FailureReason(error) == reason)
    }

    @Test func aSocketErrorUnderAnotherIsRead() {
        let error = NSError(
            domain: "Elsewhere", code: 1,
            userInfo: [NSUnderlyingErrorKey: NSError(domain: "Network.NWError", code: 57)])
        #expect(FailureReason(error) == .connectionLost)
    }

    @Test func anUnfinishedSignInFailed() {
        #expect(FailureReason(OAuthClient.Failure.stateMismatch) == .signInFailed)
        #expect(FailureReason(OAuthClient.Failure.tokenEndpoint(status: 400, error: "invalid_grant")) == .signInFailed)
        #expect(FailureReason(OAuthSession.Failure.signedOut) == .signInFailed)
    }

    @Test func anythingElseIsUnknown() {
        struct Odd: Error {}
        #expect(FailureReason(Odd()) == .unknown)
    }
}
