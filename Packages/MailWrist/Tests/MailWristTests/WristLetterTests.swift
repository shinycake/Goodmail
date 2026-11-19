import Foundation
import MailCore
import Testing

@testable import MailWrist

/// A message read in full on the watch.
struct WristLetterTests {
    private func letter(_ words: StyledText) -> WristLetter {
        WristLetter(subject: "News", words: words, extent: .whole)
    }

    @Test func linesKeepBlankOnesAndLinks() {
        var words = StyledText("Intro\n\nRead ")
        words.append("this", link: URL(string: "https://example.com"))
        var last = StyledText("Read ")
        last.append("this", link: URL(string: "https://example.com"))
        #expect(letter(words).lines == ["Intro", "", last])
    }

    @Test func aCutLetterKeepsWhatFitsInItsBytesAndSaysSo() {
        #expect(
            letter("Hello there").cut(toBytes: 5, minimum: 2)
                == WristLetter(subject: "News", words: "Hello", extent: .start))
        // Each Hebrew letter takes two bytes.
        #expect(letter("שלום עולם").cut(toBytes: 8, minimum: 2).words == "שלום")
        #expect(letter("Hello there").cut(toBytes: 1, minimum: 3).words == "Hel")
        #expect(letter("Hi").cut(toBytes: 5, minimum: 1) == letter("Hi"))
    }
}
