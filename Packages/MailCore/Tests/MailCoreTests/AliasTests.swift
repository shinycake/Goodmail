import Foundation
import MailCore
import Testing

/// Answering mail sent to one of the account's other addresses, such as a Gmail send-as alias.
struct AliasTests {
    private let me = "me@example.com"
    private let work = Contact(name: "Dana at Work", address: "dana@work.example")
    private let side = Contact(name: nil, address: "hello@side.example")
    private let avi = Contact(name: "Avi", address: "avi@example.com")

    private func message(from: Contact, to: [Contact], cc: [Contact] = []) -> Message {
        Message(
            id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: "m"), threadID: "t", from: from, to: to,
            cc: cc, subject: "Plan", date: .distantPast, body: MessageBody(plain: "Ship it?"))
    }

    @Test func aReplyGoesFromTheAliasTheMessageWasSentTo() {
        let draft = Draft.reply(
            to: message(from: avi, to: [Contact(name: nil, address: "DANA@work.example")]), all: false,
            accountEmail: me, aliases: [side, work])
        #expect(draft.alias == work)
        #expect(draft.to == [avi])
    }

    @Test func aReplyToMailForTheAccountItselfGoesFromIt() {
        let draft = Draft.reply(
            to: message(from: avi, to: [Contact(name: nil, address: me)]), all: false, accountEmail: me,
            aliases: [work])
        #expect(draft.alias == nil)
    }

    @Test func replyAllLeavesTheAccountsAliasesOut() {
        let draft = Draft.reply(
            to: message(from: avi, to: [work], cc: [side, Contact(name: nil, address: me)]), all: true,
            accountEmail: me, aliases: [work, side])
        #expect(draft.to == [avi])
        #expect(draft.cc.isEmpty)
        #expect(draft.alias == work)
    }

    @Test func answeringMyOwnMessageKeepsTheAliasItWentFrom() {
        let draft = Draft.reply(to: message(from: side, to: [avi]), all: true, accountEmail: me, aliases: [work, side])
        #expect(draft.alias == side)
        #expect(draft.to == [avi])
    }

    @Test func forwardsAndCopiesGoFromTheAliasToo() {
        #expect(Draft.forward(message(from: avi, to: [work]), aliases: [work]).alias == work)
        #expect(Draft.forwardAsAttachment(message(from: avi, to: [work]), aliases: [work]).alias == work)
        #expect(Draft.editing(message(from: work, to: [avi]), aliases: [work]).alias == work)
        #expect(Draft.editAsNew(message(from: work, to: [avi]), aliases: [work]).alias == work)
    }

    @Test func editAsNewCopiesWhatAnAliasSentAsTheAccountsOwn() throws {
        let mine = message(from: work, to: [avi])
        let theirs = Message(
            id: Message.ID(accountID: AccountID(rawValue: "a"), messageID: "n"), threadID: "t", from: avi, to: [work],
            subject: "Re: Plan", date: .distantFuture, body: MessageBody(plain: "Yes"))
        let draft = try #require(
            Answer.editAsNew.draft(answering: [mine, theirs], accountEmail: me, aliases: [work], wording: .english))
        #expect(draft.to == [avi])
        #expect(draft.alias == work)
    }

    @Test("The alias goes under its own name, else the account's")
    func theSenderIsTheAliasUnderTheRightName() {
        let account = Contact(name: "Dana Levi", address: me)
        var draft = Draft(accountID: AccountID(rawValue: "a"))
        #expect(draft.sender(account: account) == account)
        draft.alias = work
        #expect(draft.sender(account: account) == work)
        draft.alias = side
        #expect(draft.sender(account: account) == Contact(name: "Dana Levi", address: "hello@side.example"))
    }

    @Test func draftsQueuedBeforeAliasesStillDecode() throws {
        var draft = Draft(accountID: AccountID(rawValue: "a"))
        draft.alias = work
        let encoded = try JSONEncoder().encode(draft)
        var object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(try JSONDecoder().decode(Draft.self, from: encoded).alias == work)
        object["alias"] = nil
        let old = try JSONSerialization.data(withJSONObject: object)
        #expect(try JSONDecoder().decode(Draft.self, from: old).alias == nil)
    }
}
