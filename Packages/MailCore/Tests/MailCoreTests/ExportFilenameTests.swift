import Testing

@testable import MailCore

/// Files a conversation is shared as take their names from its subject.
struct ExportFilenameTests {
    @Test(
        arguments: [
            ("Plan: Thursday / Friday?", "Plan Thursday Friday.pdf"),
            ("  \n ", "Conversation.pdf"),
            ("Re:\nNotes", "Re Notes.pdf"),
        ])
    func charactersAFileNameCantHoldAreDropped(subject: String, name: String) {
        #expect(ExportFilename.name(for: subject, fallback: "Conversation", extension: "pdf") == name)
    }

    @Test func longSubjectsAreCutAtAHundredCharacters() {
        let name = ExportFilename.name(for: String(repeating: "a", count: 300), fallback: "x", extension: "txt")
        #expect(name == String(repeating: "a", count: 100) + ".txt")
    }

    @Test func severalFilesAreNumberedFromTheSecond() {
        #expect(
            ExportFilename.names(for: "Plan", count: 3, fallback: "x", extension: "eml")
                == ["Plan.eml", "Plan 2.eml", "Plan 3.eml"])
    }
}
