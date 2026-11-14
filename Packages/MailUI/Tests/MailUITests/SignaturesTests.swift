import Foundation
import MailCore
import Testing

@testable import MailUI

@MainActor
struct SignaturesTests {
    private let account = AccountID(rawValue: "a")

    @Test func anEditIsStoredWithoutTrailingBlankLines() async {
        var stored: [String] = []
        let signatures = Signatures(read: { _ in "Dana" }, store: { text, _ in stored.append(text) })
        await signatures.load(account)
        #expect(signatures.entries[account] == .saved("Dana"))

        signatures.save("Dana Levi\nGoodmail\n\n  ", for: account)
        await signatures.settled()
        #expect(stored == ["Dana Levi\nGoodmail"])
        #expect(signatures.entries[account] == .saved("Dana Levi\nGoodmail"))
    }

    @Test func anUntouchedSignatureIsNotWrittenBack() async {
        var stored: [String] = []
        let signatures = Signatures(read: { _ in "Dana" }, store: { text, _ in stored.append(text) })
        await signatures.load(account)
        signatures.save("Dana\n", for: account)
        await signatures.settled()
        #expect(stored.isEmpty, "Gmail's formatted signature stays as it is")
    }

    @Test func aRefusedEditStaysShownAndIsTriedAgain() async {
        var refuses = true
        var stored: [String] = []
        var failures = 0
        let signatures = Signatures(
            read: { _ in nil },
            store: { text, _ in
                if refuses { throw URLError(.notConnectedToInternet) }
                stored.append(text)
            })
        signatures.failed = { _ in failures += 1 }
        await signatures.load(account)
        #expect(signatures.entries[account] == .saved(""), "no signature reads as empty")

        signatures.save("Dana", for: account)
        await signatures.settled()
        #expect(failures == 1)
        #expect(signatures.entries[account] == .edited("Dana", stored: ""))

        await signatures.load(account)
        #expect(signatures.entries[account]?.text == "Dana", "reopening the editor keeps the edit")
        refuses = false
        signatures.save("Dana", for: account)
        await signatures.settled()
        #expect(stored == ["Dana"])
        #expect(signatures.entries[account] == .saved("Dana"))
    }

    @Test func quickEditsStoreTheLatest() async {
        var stored: [String] = []
        let signatures = Signatures(read: { _ in "" }, store: { text, _ in stored.append(text) })
        await signatures.load(account)
        signatures.save("D", for: account)
        signatures.save("Dana", for: account)
        await signatures.settled()
        #expect(stored == ["Dana"])
    }

    @Test func aSignatureThatCantBeReadIsReported() async {
        var failures = 0
        let signatures = Signatures(read: { _ in throw URLError(.cannotOpenFile) }, store: { _, _ in })
        signatures.failed = { _ in failures += 1 }
        await signatures.load(account)
        signatures.save("Dana", for: account)
        await signatures.settled()
        #expect(failures == 1)
        #expect(signatures.entries[account] == nil, "nothing is saved over a signature never read")
    }
}
