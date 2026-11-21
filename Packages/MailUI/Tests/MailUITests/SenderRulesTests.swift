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

    /// A window's actions, with the changes they told the window of.
    private func actions() -> (MailActions, Changes) {
        let actions = MailActions(commands: MailCommands(store: NoStore(), replay: { _ in }))
        let changes = Changes()
        actions.changed = { changes.all.append($0) }
        return (actions, changes)
    }

    private final class Changes {
        var all: [MailChange] = []
    }

    /// The window's answer to `command` for the conversation, from `sender`, which is from `conversationsFrom`.
    private func answer(
        _ command: MailCommand, for threads: [ThreadSummary.ID]? = nil, from sender: SenderAddress?,
        conversationsFrom: SenderAddress? = nil, in actions: MailActions, with rules: SenderRules
    ) -> CommandAnswer? {
        actions.senderAnswer(
            to: command, for: threads ?? [thread], from: sender, conversationsFrom: conversationsFrom ?? sender,
            with: rules)
    }

    @Test("Commands that aren't about senders pass to the screen")
    func otherCommandsPass() {
        #expect(answer(.archive, from: dana, in: actions().0, with: rules()) == nil)
    }

    @Test("Without one sender other than the reader, only Apply Rules is offered")
    func noSender() {
        let (rules, actions) = (rules(), actions().0)
        for command in [MailCommand.vipSender, .blockSender] {
            guard case .unavailable = answer(command, from: nil, in: actions, with: rules) else {
                Issue.record("\(command) should be dimmed")
                continue
            }
        }
        guard case .unavailable = answer(.applyRules, for: [], from: nil, in: actions, with: rules) else {
            Issue.record("Apply Rules with nothing picked should be dimmed")
            return
        }
    }

    @Test("Block Sender tells the window it takes the conversation away, writes the rule, then runs the rules on it")
    func blockThenApply() async throws {
        let rules = rules()
        let (actions, changes) = actions()
        try perform(answer(.blockSender, from: dana, in: actions, with: rules))
        #expect(
            changes.all == [MailChange(.block, on: [thread])], "at once, so the reader moves on before the rule runs")
        await rules.settled()
        #expect(calls.made == ["block dana@example.com as Block dana@example.com", "apply [\"t1\"]"])
    }

    @Test("Blocking someone who wrote earlier in a conversation leaves it where it is")
    func blockingAnEarlierWriterKeepsTheConversation() async throws {
        let rules = rules()
        let (actions, changes) = actions()
        let noa = try #require(SenderAddress("noa@example.com"))
        // Noa wrote its newest mail from someone else, which the rule judges it by, so it isn't trashed.
        try perform(answer(.blockSender, from: dana, conversationsFrom: noa, in: actions, with: rules))
        #expect(changes.all.isEmpty, "the reader stays on it")
        await rules.settled()
        #expect(calls.made == ["block dana@example.com as Block dana@example.com", "apply [\"t1\"]"])
    }

    @Test("The VIP command says what it will do, and the menu follows the VIPs", .timeLimit(.minutes(1)))
    func vipToggle() async throws {
        let rules = rules(vips: VIPList(["dana@example.com"]))
        let actions = actions().0
        rules.start()
        while !rules.vips.contains(dana) { await Task.yield() }
        guard case .ready(_, let title, _) = answer(.vipSender, from: dana, in: actions, with: rules) else {
            Issue.record("Expected the VIP command to be ready")
            return
        }
        #expect(title == SenderRules.vipTitle(false))

        try perform(answer(.vipSender, from: dana, in: actions, with: rules))
        #expect(!rules.vips.contains(dana), "the menu says the new state at once")
        await rules.settled()
        #expect(calls.made == ["vip dana@example.com false"])
    }
}
