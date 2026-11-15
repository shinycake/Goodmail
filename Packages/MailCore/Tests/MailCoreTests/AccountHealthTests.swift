import Foundation
import MailCore
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// An account's sync problems reach the reader when they need the reader: a sign-in the service turned down at once,
/// anything else only once it has lasted, and never a dropped connection or a device that's offline.
struct AccountHealthTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private struct Odd: Error {}

    @Test(arguments: [
        OAuthSession.Failure.signedOut as any Error,
        OAuthClient.Failure.tokenEndpoint(status: 400, error: "invalid_grant"),
        OAuthClient.Failure.tokenEndpoint(status: 400, error: "interaction_required"),
    ])
    func aTurnedDownSignInNeedsTheReaderAtOnce(error: any Error) {
        let health = AccountHealth.healthy.after(.failure(error), at: start)
        #expect(health == .needsSignIn)
        #expect(health.problem == .signInRejected)
    }

    @Test(arguments: [
        OAuthClient.Failure.tokenEndpoint(status: 503, error: nil) as any Error,
        OAuthClient.Failure.tokenEndpoint(status: 400, error: "invalid_client"),
        OAuthClient.Failure.stateMismatch,
        OAuthSession.Failure.noIDToken,
    ])
    func otherSignInFailuresAreNotTheReadersToFix(error: any Error) {
        #expect(AccountHealth.healthy.after(.failure(error), at: start) != .needsSignIn)
    }

    @Test func aFailureIsQuietAtFirst() {
        let health = AccountHealth.healthy.after(.failure(URLError(.cannotFindHost)), at: start)
        #expect(health == .faltering(.serverUnreachable, since: start))
        #expect(health.problem == nil)
    }

    @Test func aFailureThatLastsIsShown() {
        let lasted = AccountHealth.healthy
            .after(.failure(URLError(.cannotFindHost)), at: start)
            .after(.failure(Odd()), at: start.addingTimeInterval(60))
            .after(.failure(Odd()), at: start.addingTimeInterval(AccountHealth.patience))
        #expect(lasted == .failing(.unknown))
        #expect(lasted.problem == .cantSync(.unknown))
    }

    @Test func aFailureStillWithinPatienceKeepsWhenItStarted() {
        let health = AccountHealth.faltering(.timedOut, since: start)
            .after(.failure(URLError(.cannotFindHost)), at: start.addingTimeInterval(AccountHealth.patience - 1))
        #expect(health == .faltering(.serverUnreachable, since: start))
    }

    @Test(arguments: [
        AccountHealth.healthy, .faltering(.timedOut, since: Date(timeIntervalSinceReferenceDate: 0)),
        .failing(.unknown), .needsSignIn,
    ])
    func beingOfflineOrCancelledSaysNothingAboutTheAccount(health: AccountHealth) {
        let later = start.addingTimeInterval(AccountHealth.patience * 2)
        #expect(health.after(.failure(URLError(.notConnectedToInternet)), at: later) == health)
        #expect(health.after(.failure(CancellationError()), at: later) == health)
    }

    @Test func aTurnedDownSignInStaysUntilASyncWorks() {
        let later = start.addingTimeInterval(AccountHealth.patience * 2)
        #expect(AccountHealth.needsSignIn.after(.failure(URLError(.cannotFindHost)), at: later) == .needsSignIn)
        #expect(AccountHealth.needsSignIn.after(.success(()), at: later) == .healthy)
    }

    @Test(arguments: [
        AccountHealth.faltering(.timedOut, since: Date(timeIntervalSinceReferenceDate: 0)), .failing(.unknown),
    ])
    func aSyncThatWorksClearsAFailure(health: AccountHealth) {
        #expect(health.after(.success(()), at: start) == .healthy)
    }

    @Test func aProviderCanSayItsSignInWasTurnedDown() {
        struct Refused: SignInRejecting {
            var rejectsSignIn: Bool { true }
        }
        #expect(AccountHealth.healthy.after(.failure(Refused()), at: start) == .needsSignIn)
    }
}
