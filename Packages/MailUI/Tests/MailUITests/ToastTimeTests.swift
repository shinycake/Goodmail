import Testing

@testable import MailUI

@Suite("Undo toast time")
struct ToastTimeTests {
    @Test("Without VoiceOver or Switch Control a toast stays its standard time")
    func standard() {
        #expect(ToastTime.lasting(.seconds(5), assistiveTechnologyRuns: false) == .seconds(5))
    }

    @Test("VoiceOver and Switch Control get time to reach Undo")
    func assisted() {
        #expect(ToastTime.lasting(.seconds(5), assistiveTechnologyRuns: true) == ToastTime.assisted)
    }

    @Test("A toast already longer than the assisted time keeps its own")
    func longer() {
        #expect(ToastTime.lasting(.seconds(60), assistiveTechnologyRuns: true) == .seconds(60))
    }
}
