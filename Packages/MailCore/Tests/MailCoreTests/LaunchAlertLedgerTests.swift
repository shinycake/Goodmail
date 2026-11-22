import Testing

@testable import MailCore

/// Each failed send is offered once a launch, in whichever window is in front, however many windows open.
struct LaunchAlertLedgerTests {
    private struct Failed: Identifiable, Sendable {
        let id: String
    }

    @Test func offersTheFirstFailedSendUntilItIsShown() {
        var ledger = LaunchAlertLedger<Failed>()
        #expect(ledger.nextFailure == nil)
        ledger.failedNow([Failed(id: "a"), Failed(id: "b")])
        #expect(ledger.nextFailure?.id == "a", "not shown yet, as when no window could show it")
        ledger.showed("a")
        #expect(ledger.nextFailure?.id == "b")
        ledger.showed("b")
        #expect(ledger.nextFailure == nil)
    }

    @Test func aFailedSendShownOnceIsNotOfferedAgainThatLaunch() {
        var ledger = LaunchAlertLedger<Failed>()
        ledger.failedNow([Failed(id: "a")])
        ledger.showed("a")
        ledger.failedNow([])
        ledger.failedNow([Failed(id: "a")])
        #expect(ledger.nextFailure == nil, "a second window, or one opened later, doesn't show it again")
    }

    @Test func aSendThatNoLongerFailedIsNotOffered() {
        var ledger = LaunchAlertLedger<Failed>()
        ledger.failedNow([Failed(id: "a")])
        ledger.failedNow([])
        #expect(ledger.nextFailure == nil)
    }
}
