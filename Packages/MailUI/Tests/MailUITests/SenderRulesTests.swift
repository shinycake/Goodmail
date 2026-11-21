import MailCore
import Testing

@testable import MailUI

/// Apply Rules, the VIP command and Block Sender, as the Message menu and the context menus offer them.
@Suite("Sender rules")
@MainActor
struct SenderRulesTests {
    /// What the service was asked to do, in order.
    private final class Calls {
        var made: [String] = []
    }

    private let calls = Calls()
    private let dana = SenderAddress("dana@example.com")!
    private let thread = ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: "t1")

    private func rules(vips: VIPList = VIPList()) -> SenderRules {
        let calls = calls
        return SenderRules(
            service: SenderRules.Service(
                applyRules: { calls.made.append("apply \($0.map(\.threadID))") },
                block: { calls.made.append("block \($0.address) as \($1)") },
                setVIP: { calls.made.append("vip \($0.address) \($1)") },
                vips: { AsyncThrowingStream { $0.yield(vips) } }))
    }

    private func perform(_ answer: CommandAnswer?) throws {
        guard case .ready(let perform, _, _) = try #require(answer) else {
            Issue.record("Expected the command to be ready")
            return
        }
        perform()
    }

    @Test("Commands that aren't about senders pass to the screen")
    func otherCommandsPass() {
        #expect(rules().answer(to: .archive, for: [thread], from: dana) == nil)
    }

    @Test("Without one sender other than the reader, only Apply Rules is offered")
    func noSender() {
        let rules = rules()
        for command in [MailCommand.vipSender, .blockSender] {
            guard case .unavailable = rules.answer(to: command, for: [thread], from: nil) else {
                Issue.record("\(command) should be dimmed")
                continue
            }
        }
        guard case .unavailable = rules.answer(to: .applyRules, for: [], from: nil) else {
            Issue.record("Apply Rules with nothing picked should be dimmed")
            return
        }
    }

    @Test("Block Sender writes the rule, then runs the rules on the conversation it came from")
    func blockThenApply() async throws {
        let rules = rules()
        try perform(rules.answer(to: .blockSender, for: [thread], from: dana))
        await rules.settled()
        #expect(calls.made == ["block dana@example.com as Block dana@example.com", "apply [\"t1\"]"])
    }

    @Test("The VIP command says what it will do, and the menu follows the VIPs", .timeLimit(.minutes(1)))
    func vipToggle() async throws {
        let rules = rules(vips: VIPList(["dana@example.com"]))
        rules.start()
        while !rules.vips.contains(dana) { await Task.yield() }
        guard case .ready(_, let title, _) = rules.answer(to: .vipSender, for: [thread], from: dana) else {
            Issue.record("Expected the VIP command to be ready")
            return
        }
        #expect(title == SenderRules.vipTitle(false))

        try perform(rules.answer(to: .vipSender, for: [thread], from: dana))
        #expect(!rules.vips.contains(dana), "the menu says the new state at once")
        await rules.settled()
        #expect(calls.made == ["vip dana@example.com false"])
    }
}
