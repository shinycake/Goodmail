import Testing
import UIKit

@testable import MailUI

/// A Mac draws a button from its configuration only in the iPad's behavioral style.
@Suite("Configured button")
@MainActor
struct ConfiguredButtonTests {
    @Test("A button made from a configuration takes the iPad's behavioral style")
    func fromConfiguration() {
        #expect(ConfiguredButton(configuration: .plain()).preferredBehavioralStyle == .pad)
    }

    @Test("A subclass takes it too")
    func subclass() {
        #expect(MinimumTargetButton(configuration: .plain()).preferredBehavioralStyle == .pad)
    }
}
