import Foundation
import Testing

@testable import MailCore

/// The smart mailbox editor's box, as typed, and the box it saves.
struct SmartMailboxDraftTests {
    @Test func aNewBoxStartsWithOneConditionToFillIn() {
        let draft = SmartMailboxDraft()
        #expect(draft.name.isEmpty)
        #expect(draft.contents == .conditions(.all, [draft.conditions[0]]))
        #expect(draft.smartMailbox == nil, "no name, and the sender left empty")
    }

    @Test func aCompleteDraftMakesItsBox() throws {
        var draft = SmartMailboxDraft()
        draft.name = "  From Dana "
        draft.symbol = "person"
        draft.contents = .conditions(
            .any,
            [ConditionDraft(.text(.sender, .contains, "dana")), ConditionDraft(.flag(.starred, true))])
        let box = try #require(draft.smartMailbox)
        #expect(box.id == draft.id)
        #expect(box.name == .custom("From Dana"))
        #expect(box.symbol == "person")
        #expect(box.filter == .condition(.any([.text(.sender, .contains("dana")), .flag(.starred, true)])))
    }

    @Test func aBoxOpensAsTheDraftThatMadeIt() throws {
        let box = SmartMailbox(
            name: .custom("Big files"), symbol: "doc",
            filter: .condition(.all([.number(.attachmentSize, .atLeast(5_000_000))])))
        let draft = try #require(SmartMailboxDraft(box, titled: "Big files", vips: VIPList()))
        #expect(draft.name == "Big files")
        #expect(draft.smartMailbox == box)
    }

    @Test func aStartingBoxKeepsItsNameInEveryLanguageUntilRenamed() throws {
        let unread = SmartMailbox.startingSet[0]
        var draft = try #require(SmartMailboxDraft(unread, titled: "לא נקראו", vips: VIPList()))
        draft.symbol = "envelope"
        #expect(draft.smartMailbox?.name == .unread)
        draft.name = "New mail"
        #expect(draft.smartMailbox?.name == .custom("New mail"))
    }

    @Test func theVIPsBoxEditsTheVIPs() throws {
        let vips = SmartMailbox.startingSet[1]
        var draft = try #require(SmartMailboxDraft(vips, titled: "VIPs", vips: VIPList(["dana@example.com"])))
        #expect(draft.contents == .vips(["dana@example.com"]))
        draft.contents = .vips(["dana@example.com", " Noa@Example.com ", "noa@example.com", "not an address"])
        #expect(draft.vips == VIPList(["dana@example.com", "noa@example.com"]))
        #expect(draft.smartMailbox == vips)
    }

    @Test func aConditionTheEditorCantShowKeepsTheBoxFromOpeningInIt() {
        let nested = SmartMailbox(
            name: .custom("Nested"), symbol: "tray",
            filter: .condition(.all([.any([.flag(.unread, true), .flag(.starred, true)])])))
        #expect(SmartMailboxDraft(nested, titled: "Nested", vips: VIPList()) == nil)
    }

    @Test func aSearchsTermsBecomeItsConditions() throws {
        let query = SearchQuery("is:unread has:attachment from:dana subject:\"lunch plans\" tomorrow")
        let draft = try #require(SmartMailboxDraft(query: query))
        #expect(
            draft.conditions.map(\.kind) == [
                .flag(.unread, true), .flag(.hasAttachments, true), .text(.sender, .contains, "dana"),
                .text(.subject, .contains, "lunch plans"), .text(.anyText, .contains, "tomorrow"),
            ])
        #expect(draft.name == "dana, lunch plans, tomorrow", "named after what was typed")
    }

    @Test(arguments: ["", "in:sent", "category:social lunch"])
    func aSearchWithATermOnlyTheServiceKnowsCantBeSaved(text: String) {
        #expect(SmartMailboxDraft(query: SearchQuery(text)) == nil)
    }

    @Test func aBoxNeedsANameAndConditionsThatRead() {
        var unnamed = SmartMailboxDraft()
        unnamed.contents = .conditions(.all, [ConditionDraft(.flag(.unread, true))])
        #expect(unnamed.smartMailbox == nil)
        var empty = SmartMailboxDraft()
        empty.name = "Empty"
        empty.contents = .conditions(.all, [])
        #expect(empty.smartMailbox == nil)
    }
}
