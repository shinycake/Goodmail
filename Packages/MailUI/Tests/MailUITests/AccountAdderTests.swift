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

        await adder.add(.gmail)
        answer = false
        await adder.add(.gmail)
        #expect(signedIn == [.gmail, .gmail])
        #expect(added == 1, "a cancelled sign-in adds nothing")
        #expect(adder.state == .choosing)
        #expect(adder.error == nil)
    }

    @Test func aFailedSignInIsKeptToShow() async {
        struct Denied: Error {}
        let adder = AccountAdder { _ in throw Denied() }
        await adder.add(.gmail)
        #expect(adder.error is Denied)
        #expect(adder.state == .choosing)
    }

    @Test func aSecondServiceWaitsForTheFirstSignIn() async {
        var calls = 0
        let (gate, open) = AsyncStream<Void>.makeStream()
        let adder = AccountAdder { _ in
            calls += 1
            for await _ in gate { break }
            return true
        }
        let first = Task { await adder.add(.gmail) }
        while adder.state == .choosing { await Task.yield() }
        #expect(adder.state == .signingIn(.gmail))
        await adder.add(.gmail)
        #expect(calls == 1, "ignored while one is under way")
        open.yield()
        await first.value
        #expect(adder.state == .choosing)
    }
}
