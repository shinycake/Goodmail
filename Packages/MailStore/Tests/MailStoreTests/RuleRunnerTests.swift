import Foundation
import MailCore
import Testing

@testable import MailStore

/// Rules run once on each message that arrives, whichever process syncs it first, judged by the whole message.
struct RuleRunnerTests {
    private let database: MailDatabase
    private let server = FakeMailServer(accountID: AccountID(rawValue: "a1"))
    private let account = Account(
        id: AccountID(rawValue: "a1"), email: "me@example.com", color: .teal, service: .gmail)
    /// Thursday 12 November 2026, 03:45 in Jerusalem.
    private static let thursdayNight = Date(timeIntervalSince1970: 1_794_447_900)
    private static let jerusalem: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return calendar
    }()

    init() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "RuleRunnerTests-\(UUID().uuidString)")
            .appending(path: "mail.sqlite")
        database = try MailDatabase(url: url)
        try database.save(account)
    }

    private func id(_ threadID: String) -> ThreadSummary.ID {
        ThreadSummary.ID(accountID: account.id, threadID: threadID)
    }

    /// A thread whose one message arrived at `date`, with `cc` on copy, stored as a sync stores it: without a body.
    private func arrive(
        _ threadID: String, at date: Date, from sender: String = "dana@example.com", subject: String = "Yes",
        cc: Int = 0, labels: Set<String> = [SystemLabel.inbox, SystemLabel.unread]
    ) throws {
        let from = Contact(name: "Dana", address: sender)
        try database.upsert([
            ThreadSummary(
                id: id(threadID), subject: subject, snippet: "", sender: from, date: date, isUnread: true,
                messageCount: 1, labelIDs: labels)
        ])
        server.setMessages(
            [
                Message(
                    id: Message.ID(accountID: account.id, messageID: "m-\(threadID)"), threadID: threadID, from: from,
                    to: [Contact(name: nil, address: account.email)],
                    cc: (0..<cc).map { Contact(name: nil, address: "cc\($0)@example.com") }, subject: subject,
                    date: date, labelIDs: labels, body: MessageBody(plain: "Hi"))
            ], inThread: threadID)
    }

    /// A runner whose commands change `commands`, the rules' own store unless a test gives another.
    private func runner(at date: Date, commands: MailDatabase? = nil) -> RuleRunner {
        RuleRunner(
            store: database, provider: server,
            commands: MailCommands(store: commands ?? database, replay: { _ in }, now: { date }),
            calendar: Self.jerusalem, now: { date })
    }

    /// Idan's rule: mail from Dana between 3:30 and 4 on a Thursday night, with a Y in the subject and at least two
    /// more people on CC, is snoozed for two weeks.
    private let thursdayRule = MailRule(
        name: "Thursday night",
        condition: .all([
            .weekday([.thursday]),
            .timeOfDay(from: TimeOfDay(hour: 3, minute: 30), to: TimeOfDay(hour: 4, minute: 0)),
            .text(.senderAddress, .equals("dana@example.com")),
            .text(.subject, .contains("y")),
            .number(.ccCount, .atLeast(2)),
        ]),
        actions: [.snooze(seconds: 14 * 86_400), .notify(keyword: "Snoozed Dana")])

    @Test func theFirstRunStartsFromNowAndLeavesEarlierMailAlone() async throws {
        try database.setRules([thursdayRule])
        try arrive("before", at: Self.thursdayNight - 60, cc: 3)
        #expect(try await runner(at: Self.thursdayNight).run(for: account.id).alerts.isEmpty)
        #expect(try database.snoozes(of: [id("before")]).isEmpty)
        #expect(server.messageRequests.isEmpty, "nothing claimed, nothing fetched")
    }

    @Test func aMatchingMessageIsSnoozedForTwoWeeksOnceAndAlerts() async throws {
        try database.setRules([thursdayRule])
        _ = try await runner(at: Self.thursdayNight - 600).run(for: account.id)
        try arrive("t1", at: Self.thursdayNight, cc: 3)
        try arrive("few", at: Self.thursdayNight + 1, cc: 1)

        let alerts = try await runner(at: Self.thursdayNight + 120).run(for: account.id).alerts

        let wake = Self.thursdayNight + 120 + 14 * 86_400
        #expect(try database.snoozes(of: [id("t1"), id("few")]) == [id("t1"): .asleep(until: wake)])
        #expect(try database.thread(id("t1"))?.labelIDs.contains(SystemLabel.inbox) == false)
        #expect(alerts.map(\.keyword) == ["Snoozed Dana"])
        #expect(alerts.first?.thread == id("t1"))
        #expect(alerts.first?.rule == "Thursday night")
        #expect(Set(server.messageRequests) == ["t1", "few"], "the CC list is in the body, so it's fetched")
        #expect(try await runner(at: Self.thursdayNight + 240).run(for: account.id).alerts.isEmpty, "once per message")
    }

    /// The mail is claimed before the rules act on it, so an action that fails is reported, and the rest of the
    /// rules still run on every conversation and still alert.
    @Test func aFailedActionDoesntStopTheOthers() async throws {
        try database.setRules([
            MailRule(name: "Pin all", condition: .all([]), actions: [.pin, .notify(keyword: "Pinned")])
        ])
        _ = try await runner(at: Self.thursdayNight - 600).run(for: account.id)
        try arrive("a", at: Self.thursdayNight)
        try arrive("b", at: Self.thursdayNight + 1)
        // A store without the account refuses every pin.
        let elsewhere = try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "RuleRunnerTests-\(UUID().uuidString).sqlite"))

        let run = try await runner(at: Self.thursdayNight + 60, commands: elsewhere).run(for: account.id)

        #expect(run.failures.map(\.thread) == [id("a"), id("b")])
        #expect(run.failures.map(\.rule) == ["Pin all", "Pin all"])
        #expect(run.alerts.map(\.thread) == [id("a"), id("b")])
    }

    @Test func mailFromMeSpamAndTrashAreLeftAlone() async throws {
        try database.setRules([MailRule(name: "Star all", condition: .all([]), actions: [.star])])
        _ = try await runner(at: Self.thursdayNight - 600).run(for: account.id)
        try arrive("mine", at: Self.thursdayNight, from: account.email)
        try arrive("spam", at: Self.thursdayNight, labels: [SystemLabel.spam])
        try arrive("theirs", at: Self.thursdayNight)

        _ = try await runner(at: Self.thursdayNight + 60).run(for: account.id)

        #expect(try database.thread(id("theirs"))?.labelIDs.contains(SystemLabel.starred) == true)
        #expect(try database.thread(id("mine"))?.labelIDs.contains(SystemLabel.starred) == false)
        #expect(try database.thread(id("spam"))?.labelIDs.contains(SystemLabel.starred) == false)
        #expect(!server.messageRequests.contains("spam"))
    }

    @Test func aRunTakesTheOldestFirstAndLeavesTheRestForTheNext() throws {
        _ = try database.claimRuleMail(in: account.id, now: Self.thursdayNight - 600, limit: 2)
        for (index, name) in ["a", "b", "c"].enumerated() {
            try arrive(name, at: Self.thursdayNight + Double(index))
        }
        #expect(try database.claimRuleMail(in: account.id, now: Self.thursdayNight, limit: 2) == [id("a"), id("b")])
        #expect(try database.claimRuleMail(in: account.id, now: Self.thursdayNight, limit: 2) == [id("c")])
        #expect(try database.claimRuleMail(in: account.id, now: Self.thursdayNight, limit: 2).isEmpty)
    }

    @Test func rulesKeepTheirOrder() throws {
        let rules = [
            MailRule(name: "B", condition: .flag(.unread, true), actions: [.markRead]),
            MailRule(name: "A", condition: .all([]), actions: [.pin]),
        ]
        try database.setRules(rules)
        #expect(try database.rules() == rules)
        try database.setRules(Array(rules.reversed()))
        #expect(try database.rules().map(\.name) == ["A", "B"])
    }
}
