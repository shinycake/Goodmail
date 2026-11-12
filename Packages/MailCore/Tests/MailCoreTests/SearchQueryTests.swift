import MailCore
import Testing

struct SearchQueryTests {
    @Test func readsWordsAndOperators() {
        let query = SearchQuery(
            "  lunch From:dana@example.com has:attachment 10:30 subject:\"team plans\" \"exact phrase\"")
        #expect(
            query.terms == [
                .word("lunch"), .from("dana@example.com"), .hasAttachment, .word("10:30"), .subject("team plans"),
                .word("exact phrase"),
            ])
        #expect(
            query.text == "lunch from:dana@example.com has:attachment 10:30 subject:\"team plans\" \"exact phrase\"")
    }

    @Test func aColonWithNothingAfterItIsAWord() {
        #expect(SearchQuery("note: x").terms == [.word("note:"), .word("x")])
        #expect(SearchQuery("from:").terms == [.word("from:")])
        #expect(SearchQuery(" \"\" ").isEmpty)
        #expect(SearchQuery("subject:\"open").terms == [.subject("open")])
    }
}
