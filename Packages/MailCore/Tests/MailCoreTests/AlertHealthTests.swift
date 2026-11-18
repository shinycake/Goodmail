import Foundation
import MailCore
import Testing

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The reader hears that an account's alerts are paused only once the mail server has kept refusing the relay's
/// login, and never for a failure that says nothing about the login.
struct AlertHealthTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let refused = Result<Void, any Error>.failure(PushRelayClient.Failure.loginRefused)

    @Test func aRefusalIsQuietAtFirst() {
        let health = AlertHealth.working.after(refused, at: start)
        #expect(health == .refused(since: start))
        #expect(health.after(refused, at: start.addingTimeInterval(AccountHealth.patience - 1)) == health)
    }

    @Test func aRefusalThatLastsPausesTheAlerts() {
        let lasted = AlertHealth.working
            .after(refused, at: start)
            .after(refused, at: start.addingTimeInterval(AccountHealth.patience))
        #expect(lasted == .paused)
        #expect(lasted.after(refused, at: start.addingTimeInterval(AccountHealth.patience * 2)) == .paused)
    }

    @Test(arguments: [AlertHealth.refused(since: Date(timeIntervalSinceReferenceDate: 0)), .paused])
    func aRegistrationTheRelayTakesClearsIt(health: AlertHealth) {
        #expect(health.after(.success(()), at: start) == .working)
    }

    @Test(arguments: [
        AlertHealth.working, .refused(since: Date(timeIntervalSinceReferenceDate: 0)), .paused,
    ])
    func otherFailuresSayNothingAboutTheLogin(health: AlertHealth) {
        let later = start.addingTimeInterval(AccountHealth.patience * 2)
        #expect(health.after(.failure(URLError(.notConnectedToInternet)), at: later) == health)
        #expect(health.after(.failure(PushRelayClient.Failure.unauthorized), at: later) == health)
        #expect(health.after(.failure(PushRelayClient.Failure.status(503)), at: later) == health)
    }
}
