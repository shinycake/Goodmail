import MailCore
import Testing

/// A narrow window's one stack holds one reader at most: a conversation opened over another takes its place (R1).
struct ReaderStackTests {
    @Test func aReaderOpensOverTheListWhenNoneIsOnShow() {
        #expect(ReaderStack(readers: [false, false]) == .push)
        #expect(ReaderStack(readers: []) == .push)
    }

    @Test func aReaderTakesThePlaceOfTheOneOnShow() {
        #expect(ReaderStack(readers: [false, false, true]) == .replace(keeping: 2))
    }

    @Test func everythingFromTheFirstReaderUpGoes() {
        // Two readers stacked by an older build of the window, or a screen pushed over the reader.
        #expect(ReaderStack(readers: [false, false, true, true]) == .replace(keeping: 2))
        #expect(ReaderStack(readers: [false, true, false]) == .replace(keeping: 1))
    }
}
