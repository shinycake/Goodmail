import MailCore
import Testing

/// What opens after the reader puts a conversation away, as Settings keeps it.
struct AfterRemovalTests {
    @Test func theNextConversationOpensUnlessTheReaderChoseTheList() {
        #expect(AfterRemoval.standard == .next, "as iOS Mail does")
        #expect(AfterRemoval(stored: nil) == .next)
        #expect(AfterRemoval(stored: "list") == .list)
        #expect(AfterRemoval(stored: "next") == .next)
    }

    @Test func aChoiceThisBuildDoesntKnowReadsAsTheStandardOne() {
        #expect(AfterRemoval(stored: "previous") == .standard)
        #expect(AfterRemoval(stored: "") == .standard)
    }

    @Test(arguments: AfterRemoval.allCases)
    func eachChoiceReadsBackAsStored(choice: AfterRemoval) {
        #expect(AfterRemoval(stored: choice.rawValue) == choice)
    }
}
