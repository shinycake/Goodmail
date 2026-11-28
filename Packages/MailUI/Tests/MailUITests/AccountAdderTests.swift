import Foundation
import MailCore
import Testing

@testable import MailUI

/// Adding an account signs in to the picked service, one sign-in at a time.
@MainActor
struct AccountAdderTests {
    @Test func everyServiceIsOffered() {
        #expect(AccountAdder(signIn: { _ in true }).services == MailService.allCases)
    }

    @Test func anAddedAccountIsReportedAndACancelledOneIsNot() async {
        var signedIn: [MailService] = []
        var answer = true
        let adder = AccountAdder { service in
            signedIn.append(service)
            return answer
        }
        var added = 0
        adder.onAdded = { added += 1 }

        adder.add(.gmail)
        await adder.settled()
        answer = false
        adder.add(.gmail)
        await adder.settled()
        #expect(signedIn == [.gmail, .gmail])
        #expect(added == 1, "a cancelled sign-in adds nothing")
        #expect(adder.signingIn == nil)
        #expect(adder.failure == nil)
    }

    @Test func aFailedSignInIsKeptToShowUntilDismissed() async {
        struct Denied: Error {}
        let adder = AccountAdder { _ in throw Denied() }
        adder.add(.gmail)
        await adder.settled()
        #expect(adder.failure is Denied)
        #expect(adder.signingIn == nil)

        adder.dismissFailure()
        #expect(adder.failure == nil)
    }

    @Test func aSignInAfterAFailureClearsIt() async {
        struct Denied: Error {}
        var fails = true
        let adder = AccountAdder { _ in
            if fails { throw Denied() }
            return true
        }
        adder.add(.gmail)
        await adder.settled()
        fails = false
        adder.add(.gmail)
        await adder.settled()
        #expect(adder.failure == nil, "the alert is about the last sign-in, which worked")
    }

    @Test func aSecondServiceWaitsForTheFirstSignIn() async {
        var calls = 0
        let (gate, open) = AsyncStream<Void>.makeStream()
        let adder = AccountAdder { _ in
            calls += 1
            for await _ in gate { break }
            return true
        }
        adder.add(.gmail)
        #expect(adder.signingIn == .gmail, "the adder signs in on its own, with no one waiting")
        adder.add(.outlook)
        #expect(adder.signingIn == .gmail)
        open.yield()
        await adder.settled()
        #expect(calls == 1, "ignored while one is under way")
        #expect(adder.signingIn == nil)
    }
}
