import Foundation
import MailCore
import Testing

@testable import MailUI

/// Alerts explain a failure in words, not as an error's type and number.
struct FailureMessageTests {
    @Test func aDroppedSocketSaysTheConnectionWasLost() {
        let message = FailureReason.message(for: NSError(domain: "Network.NWError", code: 57))
        #expect(message == FailureReason.connectionLost.message)
        #expect(!message.contains("NWError"))
    }

    @Test func anErrorThatExplainsItselfKeepsItsWords() {
        struct Explained: LocalizedError {
            var errorDescription: String? { "The Keychain is locked." }
        }
        #expect(FailureReason.message(for: Explained()) == "The Keychain is locked.")
    }

    @Test func anyOtherErrorGetsAPlainSentence() {
        struct Odd: Error {}
        #expect(FailureReason.message(for: Odd()) == FailureReason.unknown.message)
    }
}
