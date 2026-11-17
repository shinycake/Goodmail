import Foundation
import Testing

@testable import MailCore

/// Filters and rules ask any field of a mail, and a mail only listed so far answers only what it knows.
struct MailConditionTests {
    static let account = Account(
        id: AccountID(rawValue: "a"), email: "me@example.com", color: .blue, service: .gmail,
        aliases: [Contact(name: nil, address: "alias@example.com")])

    /// Thursday 2026-11-12, 03:45 in Jerusalem.
    static let thursdayNight = Date(timeIntervalSince1970: 1_794_447_900)

    static let jerusalem: MailCondition.Context = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Jerusalem")!
        return MailCondition.Context(now: thursdayNight.addingTimeInterval(3600), calendar: calendar)
    }()

    static func message(
        from sender: Contact = Contact(name: "Dana Levi", address: "dana@shop.com"),
        to: [Contact] = [Contact(name: nil, address: "me@example.com")],
        cc: [Contact] = [], subject: String = "Your order", body: String = "Total: $65.08",
        labels: Set<String> = [SystemLabel.inbox, SystemLabel.unread], date: Date = thursdayNight,
        attachments: [MailCore.Attachment] = [], references: [String] = []
    ) -> MailFacts {
        let message = Message(
            id: Message.ID(accountID: account.id, messageID: "m"), threadID: "t", from: sender, to: to, cc: cc,
            subject: subject, date: date, labelIDs: labels, body: MessageBody(plain: body),
            attachments: attachments, references: references)
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t"), subject: subject, snippet: "", sender: sender,
            date: date, isUnread: true, messageCount: 3, labelIDs: labels)
        return MailFacts(
            message: message, bodyText: body, thread: thread, account: account,
            labelNames: [SystemLabel.inbox: "Inbox", "Label_7": "Receipts"])
    }

    static func listed(subject: String = "Your order") -> MailFacts {
        let thread = ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: "t"), subject: subject, snippet: "",
            sender: Contact(name: "Dana", address: "dana@shop.com"), date: thursdayNight, isUnread: true,
            messageCount: 1, labelIDs: [SystemLabel.inbox])
        return MailFacts(thread: thread, account: account)
    }

    @Test func idansRuleMatchesTheMailItDescribes() {
        // From Dana, Thursday between 3:30 and 4 at night, a "Y" in the subject, and at least 2 people on Cc.
        let rule = MailCondition.all([
            .text(.senderAddress, .equals("dana@shop.com")),
            .weekday([.thursday]),
            .timeOfDay(from: TimeOfDay(hour: 3, minute: 30), to: TimeOfDay(hour: 4, minute: 0)),
            .text(.subject, .contains("y")),
            .number(.ccCount, .atLeast(2)),
        ])
        let twoOnCc = [Contact(name: nil, address: "b@x.com"), Contact(name: nil, address: "c@x.com")]
        #expect(rule.matches(Self.message(cc: twoOnCc), in: Self.jerusalem))
        #expect(!rule.matches(Self.message(cc: [twoOnCc[0]]), in: Self.jerusalem))
        #expect(!rule.matches(Self.message(cc: twoOnCc, subject: "Shipped"), in: Self.jerusalem))
        let anHourLater = Self.thursdayNight.addingTimeInterval(3600)
        #expect(!rule.matches(Self.message(cc: twoOnCc, date: anHourLater), in: Self.jerusalem))
    }

    @Test(
        arguments: [
            (TextMatch.contains("ORDER"), true), (.contains("ördér"), true), (.equals("your order"), true),
            (.equals("order"), false), (.beginsWith("your"), true), (.endsWith("order"), true),
            (.matchesPattern("^y.*r$"), true), (.matchesPattern("("), false), (.isEmpty, false),
        ])
    func textIgnoresCaseAndDiacritics(match: TextMatch, expected: Bool) {
        #expect(MailCondition.text(.subject, match).matches(Self.message()) == expected)
    }

    @Test func aRecipientMatchesByNameOrAddress() {
        let mail = Self.message(cc: [Contact(name: "Noa Cohen", address: "noa@work.com")])
        #expect(MailCondition.text(.cc, .contains("noa cohen")).matches(mail))
        #expect(MailCondition.text(.recipients, .endsWith("@work.com")).matches(mail))
        #expect(!MailCondition.text(.to, .contains("noa")).matches(mail))
    }

    @Test func theSenderDomainAndMailboxNamesAreText() {
        let mail = Self.message(labels: [SystemLabel.inbox, "Label_7"])
        #expect(MailCondition.text(.senderDomain, .equals("shop.com")).matches(mail))
        #expect(MailCondition.text(.mailbox, .equals("receipts")).matches(mail))
    }

    @Test func amountsComeFromTheBody() {
        let mail = Self.message(body: "Echo Dot $49.99\nOrder total: $65.08")
        #expect(MailCondition.number(.totalAmount, .greaterThan(60)).matches(mail))
        #expect(MailCondition.number(.largestAmount, .between(65, 66)).matches(mail))
        #expect(!MailCondition.number(.totalAmount, .greaterThan(60)).matches(Self.message(body: "Thanks!")))
    }

    @Test func aListedConversationLeavesWhatItCantKnowUnknown() {
        let mail = Self.listed()
        #expect(!MailCondition.text(.body, .contains("order")).matches(mail))
        #expect(!MailCondition.not(.text(.body, .contains("order"))).matches(mail))
        #expect(MailCondition.any([.text(.body, .contains("x")), .text(.subject, .contains("order"))]).matches(mail))
        #expect(!MailCondition.all([.text(.body, .contains("x")), .text(.subject, .contains("order"))]).matches(mail))
        #expect(MailCondition.text(.subject, .contains("order")).matches(mail))
    }

    @Test func groupsCombineAsTheirNamesSay() {
        let mail = Self.message()
        #expect(MailCondition.all([]).matches(mail))
        #expect(!MailCondition.any([]).matches(mail))
        #expect(MailCondition.not(.flag(.starred, true)).matches(mail))
    }

    @Test func flagsReadLabelsAccountAndDevice() {
        let mine = Self.message(from: Contact(name: nil, address: "ALIAS@example.com"))
        #expect(MailCondition.flag(.fromMe, true).matches(mine))
        #expect(MailCondition.flag(.toMe, true).matches(Self.message()))
        #expect(MailCondition.flag(.reply, true).matches(Self.message(subject: "Re: lunch")))
        #expect(MailCondition.flag(.reply, true).matches(Self.message(references: ["<a@b>"])))
        #expect(MailCondition.flag(.forward, true).matches(Self.message(subject: "Fwd: lunch")))
        #expect(MailCondition.flag(.archived, true).matches(Self.message(labels: ["Label_7"])))
        var pinned = Self.message()
        pinned.local = MailFacts.Local(isPinned: true, snooze: .asleep(until: Self.thursdayNight))
        #expect(MailCondition.flag(.pinned, true).matches(pinned))
        #expect(MailCondition.flag(.snoozed, true).matches(pinned))
        #expect(MailCondition.date(.snoozedUntil, .before(.distantFuture)).matches(pinned))
    }

    @Test func attachmentsAreCountedWithoutInlineImages() {
        let files = [
            MailCore.Attachment(id: "1", filename: "invoice.pdf", mimeType: "application/pdf", size: 1000),
            MailCore.Attachment(id: "2", filename: "logo.png", mimeType: "image/png", size: 50, isInline: true),
        ]
        let mail = Self.message(attachments: files)
        #expect(MailCondition.number(.attachmentCount, .equals(1)).matches(mail))
        #expect(MailCondition.number(.attachmentSize, .equals(1000)).matches(mail))
        #expect(MailCondition.text(.attachmentType, .equals("application/pdf")).matches(mail))
        #expect(MailCondition.flag(.hasAttachments, true).matches(mail))
    }

    @Test func aTimeRangeCanRunPastMidnight() {
        let lateNight = MailCondition.timeOfDay(
            from: TimeOfDay(hour: 23, minute: 0), to: TimeOfDay(hour: 4, minute: 0))
        #expect(lateNight.matches(Self.message(), in: Self.jerusalem))
        let morning = MailCondition.timeOfDay(from: TimeOfDay(hour: 4, minute: 0), to: TimeOfDay(hour: 12, minute: 0))
        #expect(!morning.matches(Self.message(), in: Self.jerusalem))
    }

    @Test func aRelativeDateIsReadAgainstNow() {
        #expect(MailCondition.date(.date, .withinLast(seconds: 7200)).matches(Self.message(), in: Self.jerusalem))
        #expect(!MailCondition.date(.date, .withinLast(seconds: 60)).matches(Self.message(), in: Self.jerusalem))
    }
}

/// A store reads only the dates a condition allows.
struct MailConditionBoundsTests {
    let now = Date(timeIntervalSince1970: 1_000_000)

    @Test func topLevelDatesNarrowTheBounds() {
        let condition = MailCondition.all([
            .date(.date, .withinLast(seconds: 100)), .date(.date, .before(Date(timeIntervalSince1970: 999_950))),
            .text(.subject, .contains("x")),
        ])
        let bounds = condition.dateBounds(now: now)
        #expect(bounds.from == Date(timeIntervalSince1970: 999_900))
        #expect(bounds.to == Date(timeIntervalSince1970: 999_950))
    }

    @Test func datesInsideOtherGroupsLeaveTheBoundsOpen() {
        let condition = MailCondition.any([.date(.date, .after(now)), .flag(.unread, true)])
        #expect(condition.dateBounds(now: now).from == nil)
        #expect(MailCondition.not(.date(.date, .after(now))).dateBounds(now: now).from == nil)
        #expect(MailCondition.date(.snoozedUntil, .after(now)).dateBounds(now: now).from == nil)
    }
}
