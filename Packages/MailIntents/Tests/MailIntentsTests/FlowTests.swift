import AppIntents
import Foundation
import MailCore
import Testing
import UniformTypeIdentifiers

@testable import MailIntents

/// What one action hands the next: senders to Find, messages to their conversations, conversations to their
/// messages, and messages to files.
struct FlowTests {
    private let account = Account(
        id: AccountID(rawValue: "A1"), email: "me@example.com", color: .teal, service: .gmail)
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let dana = Contact(name: "Dana", address: "Dana@Example.com")
    private let shop = Contact(name: "Shop", address: "news@shop.com")

    private func thread(_ id: String, from sender: Contact, daysAgo: Double, count: Int = 1) -> ThreadSummary {
        ThreadSummary(
            id: ThreadSummary.ID(accountID: account.id, threadID: id), subject: "Plan", snippet: "", sender: sender,
            date: now - daysAgo * DaysOld.day, isUnread: false, messageCount: count, labelIDs: [SystemLabel.inbox])
    }

    private func message(
        _ id: String, in thread: ThreadSummary, minutesAgo: Double = 0, attachments: [MailCore.Attachment] = []
    ) -> Message {
        Message(
            id: Message.ID(accountID: account.id, messageID: id), threadID: thread.id.threadID, from: thread.sender,
            to: [Contact(name: nil, address: account.email)], subject: thread.subject,
            date: thread.date - minutesAgo * 60, labelIDs: [SystemLabel.inbox], body: MessageBody(plain: "Hi"),
            attachments: attachments)
    }

    private func catalog(_ host: FakeHost) -> Catalog { Catalog(host: host, now: now) }

    // MARK: Senders

    @Test func theSenderPickerOffersWhoWritesMostThenWhoWroteLast() async throws {
        let host = FakeHost(
            accountList: [account],
            stored: [
                thread("t1", from: shop, daysAgo: 1), thread("t2", from: dana, daysAgo: 2),
                thread("t3", from: Contact(name: nil, address: "dana@example.com"), daysAgo: 3),
                thread("t4", from: Contact(name: nil, address: account.email), daysAgo: 4),
            ])
        let senders = try await catalog(host).frequentSenders()
        #expect(senders.map(\.id) == ["dana@example.com", "news@shop.com"], "most first, and never the account")
        #expect(senders.first?.name == "Dana", "named as the conversation that named them")
        #expect(senders.first?.domain == "example.com")
    }

    @Test func aTypedAddressCanBeChosenEvenIfItNeverWrote() async throws {
        let host = FakeHost(accountList: [account], stored: [thread("t1", from: dana, daysAgo: 1)])
        let found = try await catalog(host).senders(matching: "Avi <avi@example.org>")
        #expect(found.map(\.address) == ["avi@example.org"])
        #expect(found.first?.name == "Avi")
        #expect(try await catalog(host).senders(matching: "dan").map(\.id) == ["dana@example.com"])
        #expect(try await catalog(host).senders(matching: "avi").isEmpty, "not an address, and nobody by that name")
    }

    @Test func aSenderResolvesByAddressWhetherOrNotItWrote() async throws {
        let host = FakeHost(accountList: [account], stored: [thread("t1", from: dana, daysAgo: 1)])
        let senders = try await catalog(host).senders(["dana@example.com", "avi@example.org"])
        #expect(senders.map(\.name) == ["Dana", ""])
        #expect(senders.map(\.address) == ["Dana@Example.com", "avi@example.org"])
    }

    @Test(arguments: ["a@b.co", "Dana.Levi+x@mail.example.com"])
    func addressesReadAsAddresses(_ text: String) {
        #expect(Catalog.looksLikeAddress(text))
    }

    @Test(arguments: ["dana", "@b.co", "a@b", "a@b.", "a b@c.d", "a@@b.co"])
    func otherTextDoesNot(_ text: String) {
        #expect(!Catalog.looksLikeAddress(text))
    }

    // MARK: Days Old

    @Test func daysOldCountsWholeDays() {
        #expect(DaysOld.of(now - 6.9 * DaysOld.day, now: now) == 6)
        #expect(DaysOld.of(now - 7 * DaysOld.day, now: now) == 7)
        #expect(DaysOld.of(now + 60, now: now) == 0)
    }

    @Test func olderThanAWeekFindsWhatAnEntityCallsOlder() async throws {
        let host = FakeHost(
            accountList: [account],
            stored: [
                thread("new", from: shop, daysAgo: 6.5), thread("week", from: shop, daysAgo: 7.5),
                thread("old", from: shop, daysAgo: 30),
            ])
        let context = MailCondition.Context(now: now)
        func found(_ condition: MailCondition) throws -> [String] {
            try host.threadFacts(matching: condition, in: context).map(\.envelope.thread.threadID).sorted()
        }
        #expect(try found(DaysOld.atLeast(7, now: now)) == ["old", "week"])
        #expect(try found(DaysOld.atLeast(8, now: now)) == ["old"], "greater than 7")
        #expect(try found(DaysOld.atMost(6, now: now)) == ["new"], "less than 7")
        #expect(try found(DaysOld.exactly(7, now: now)) == ["week"])
        #expect(try found(DaysOld.between(10, 6, now: now)) == ["new", "week"])
        let entities = try await catalog(host).threads(["A1/new", "A1/week"])
        #expect(entities.map(\.daysOld) == [6, 7])
    }

    // MARK: Messages and conversations

    @Test func aMessageNamesItsSenderAndItsConversation() async throws {
        let plan = thread("t1", from: dana, daysAgo: 2, count: 3)
        let host = FakeHost(accountList: [account], stored: [plan], cached: [plan.id: [message("m1", in: plan)]])
        let entity = try #require(try await catalog(host).messages(["A1/t1/m1"]).first)
        #expect(entity.from.id == "dana@example.com")
        #expect(entity.daysOld == 2)
        #expect(entity.conversation.id == "A1/t1")
        #expect(entity.conversation.messageCount == 3, "the conversation's own facts, not the message's")
    }

    @Test func gettingMessagesFetchesWhatTheDeviceLacks() async throws {
        let plan = thread("t1", from: dana, daysAgo: 0, count: 2)
        let host = FakeHost(
            accountList: [account], stored: [plan], cached: [plan.id: [message("m1", in: plan, minutesAgo: 10)]],
            onServer: [plan.id: [message("m2", in: plan)]])
        let all = try await catalog(host).messages(ofThreads: ["A1/t1"], latestOnly: false)
        #expect(all.map(\.id) == ["A1/t1/m1", "A1/t1/m2"], "oldest first, the fetched one included")
        #expect(host.performed.loaded(plan.id))
        let latest = try await catalog(host).messages(ofThreads: ["A1/t1"], latestOnly: true)
        #expect(latest.map(\.id) == ["A1/t1/m2"])
    }

    @Test func gettingMessagesOfNothingOnTheDeviceFails() async {
        let host = FakeHost(accountList: [account])
        await #expect(throws: IntentError.self) {
            try await catalog(host).messages(ofThreads: ["nonsense"], latestOnly: false)
        }
    }

    // MARK: Files

    @Test func attachmentsDownloadWithoutInlinePicturesUnlessAsked() async throws {
        let plan = thread("t1", from: dana, daysAgo: 0)
        let files = [
            MailCore.Attachment(id: "1", filename: "invoice.pdf", mimeType: "application/pdf", size: 10),
            MailCore.Attachment(id: "2", filename: "logo.png", mimeType: "image/png", size: 10, isInline: true),
        ]
        let host = FakeHost(
            accountList: [account], stored: [plan], cached: [plan.id: [message("m1", in: plan, attachments: files)]])
        let saved = try await catalog(host).attachments(ofMessages: ["A1/t1/m1"], includingInline: false)
        #expect(saved.map(\.filename) == ["invoice.pdf"])
        #expect(saved.first?.data == Data("m1/invoice.pdf".utf8))
        #expect(saved.first?.type == .pdf)
        let all = try await catalog(host).attachments(ofMessages: ["A1/t1/m1"], includingInline: true)
        #expect(all.map(\.filename) == ["invoice.pdf", "logo.png"])
    }

    @Test func emailFilesAreNamedForTheirSubjectsWithoutClashing() async throws {
        let plan = thread("t1", from: dana, daysAgo: 0)
        let host = FakeHost(
            accountList: [account], stored: [plan],
            cached: [plan.id: [message("m1", in: plan, minutesAgo: 5), message("m2", in: plan)]])
        let files = try await catalog(host).emailFiles(ofMessages: ["A1/t1/m1", "A1/t1/m2"])
        #expect(files.map(\.filename) == ["Plan.eml", "Plan 2.eml"])
        #expect(files.first?.data == Data("Source of m1".utf8))
    }
}
