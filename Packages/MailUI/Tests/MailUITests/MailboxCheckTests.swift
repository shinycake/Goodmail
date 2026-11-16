import Testing

@testable import MailUI

/// The alert filter switch shows what the server says, and a switch that doesn't go through leaves it as it was.
@MainActor
struct MailboxCheckTests {
    private func check(
        isOn: Bool?, turnOn: @escaping () -> Bool = { true }, turnOff: @escaping () -> Bool = { true }
    ) -> MailboxCheck {
        MailboxCheck(service: MailboxCheck.Service(isOn: { isOn }, turnOn: { turnOn() }, turnOff: { turnOff() }))
    }

    @Test(arguments: [(true, MailboxCheck.State.on), (false, .off), (nil, .unknown)] as [(Bool?, MailboxCheck.State)])
    func loadingShowsWhatTheServerSays(isOn: Bool?, state: MailboxCheck.State) async {
        let check = check(isOn: isOn)
        await check.load()
        #expect(check.state == state)
    }

    @Test func turningOnAsksGoogleAndTurningOffAsksTheServer() async {
        var calls: [String] = []
        let check = check(
            isOn: false,
            turnOn: {
                calls.append("on")
                return true
            },
            turnOff: {
                calls.append("off")
                return true
            })
        await check.load()
        await check.set(true)
        #expect(check.state == .on)
        await check.set(false)
        #expect(check.state == .off)
        #expect(calls == ["on", "off"])
    }

    @Test func aCancelledOrFailedSwitchLeavesItAsItWas() async {
        let check = check(isOn: false, turnOn: { false })
        await check.load()
        await check.set(true)
        #expect(check.state == .off)
    }

    @Test func nothingSwitchesWhileTheStatusIsUnknown() async {
        var asked = false
        let check = check(
            isOn: nil,
            turnOn: {
                asked = true
                return true
            })
        await check.load()
        await check.set(true)
        #expect(check.state == .unknown)
        #expect(!asked)
    }
}
