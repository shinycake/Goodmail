import Foundation
import MailCore
import Testing

@testable import MailWrist

/// Commands cross between devices that may run different versions, and Undo sends their inverse.
struct WristCommandTests {
    static let kinds: [WristCommand.Kind] = [
        .archive, .moveToInbox, .trash, .untrash, .markRead(true), .markRead(false), .pin(true), .pin(false),
    ]

    @Test(arguments: kinds)
    func theInverseOfTheInverseIsTheCommand(kind: WristCommand.Kind) {
        #expect(kind.inverse?.inverse == kind)
        #expect(kind.inverse != kind)
    }

    @Test func aReplyCantBeTakenBack() {
        #expect(WristCommand.Kind.reply("Thanks!").inverse == nil)
        #expect(WristCommand(threads: [], kind: .reply("Thanks!"), madeAt: .now).inverse(madeAt: .now) == nil)
    }

    @Test func keepsItsWireFormat() throws {
        let command = WristCommand(
            id: try #require(UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF")),
            threads: [ThreadSummary.ID(accountID: AccountID(rawValue: "a1"), threadID: "t1")], kind: .markRead(true),
            madeAt: Date(timeIntervalSinceReferenceDate: 0))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let json = String(decoding: try encoder.encode(command), as: UTF8.self)
        #expect(
            json
                == #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":{"markRead":{"_0":true}},"madeAt":0,"#
                + #""threads":[{"accountID":"a1","threadID":"t1"}]}"#)
        #expect(try JSONDecoder().decode(WristCommand.self, from: Data(json.utf8)) == command)
    }
}
