import Testing

@testable import MailCore

struct RecipientEntryTests {
    private let dana = Contact(name: "Dana Levi", address: "dana@example.com")
    private let avi = Contact(name: "Avi", address: "avi@example.com")
    private let noa = Contact(name: nil, address: "noa@example.com")

    @Test func aSeparatorTurnsWhatIsTypedIntoATokenAndKeepsTheRest() {
        var entry = RecipientEntry()
        entry.type("dana@example.com")
        #expect(entry.contacts.isEmpty)
        #expect(entry.all.map(\.address) == ["dana@example.com"], "typed text still counts as a recipient")
        entry.type("dana@example.com, av")
        #expect(entry.contacts.map(\.address) == ["dana@example.com"])
        #expect(entry.typed == "av")
    }

    @Test(arguments: [
        "\"Levi, Dana\" <dana@example.com>; Avi <avi@example.com>\nnoa@example.com,",
        "\"Levi, Dana\" <dana@example.com>, Avi <avi@example.com>, noa@example.com;",
    ])
    func aPastedListBecomesTokens(pasted: String) {
        var entry = RecipientEntry()
        entry.type(pasted)
        #expect(entry.contacts.map(\.address) == ["dana@example.com", "avi@example.com", "noa@example.com"])
        #expect(entry.contacts.first?.name == "Levi, Dana", "a comma inside quotes is part of the name")
        #expect(entry.typed.isEmpty)
    }

    @Test func committingTokenizesAndSkipsAddressesAlreadyThere() {
        var entry = RecipientEntry([dana])
        entry.type("DANA@example.com")
        entry.commit()
        #expect(entry.contacts == [dana])
        entry.complete(with: avi)
        #expect(entry.contacts == [dana, avi])
        #expect(entry.focus == .typing(""))
    }

    @Test func deleteSelectsTheLastTokenThenRemovesIt() {
        var entry = RecipientEntry([dana, avi])
        entry.type("x")
        var handled = entry.deleteBackward()
        #expect(!handled, "a typed character goes first")
        entry.type("")
        handled = entry.deleteBackward()
        #expect(handled)
        #expect(entry.focus == .selected(1))
        handled = entry.deleteBackward()
        #expect(handled)
        #expect(entry.contacts == [dana])
        #expect(entry.focus == .typing(""))
    }

    @Test func selectingATokenKeepsWhatWasTyped() {
        var entry = RecipientEntry([dana])
        entry.type("avi@example.com")
        entry.select(0)
        #expect(entry.contacts.map(\.address) == ["dana@example.com", "avi@example.com"])
        #expect(entry.selected == 0)
        entry.deselect()
        #expect(entry.focus == .typing(""))
    }

    @Test func aTokenMovesBetweenFieldsAndWithinOne() {
        var recipients = Recipients(to: [dana, avi, noa])
        recipients.move(0, from: .to, to: .cc, at: 0)
        #expect(recipients.to.contacts == [avi, noa])
        #expect(recipients.cc.contacts == [dana])
        recipients.move(0, from: .to, to: .to, at: 2)
        #expect(recipients.to.contacts == [noa, avi], "dropped after the last token")
        recipients.move(0, from: .cc, to: .to, at: 99)
        #expect(recipients.to.contacts == [noa, avi, dana])
        #expect(recipients.all == [noa, avi, dana])
    }

    @Test func aTokenTypesBackAsItWouldBeParsed() {
        let quoted = Contact(name: "Levi, Dana", address: "dana@example.com")
        #expect(quoted.typedForm == "\"Levi, Dana\" <dana@example.com>")
        #expect(noa.typedForm == "noa@example.com")
        var entry = RecipientEntry()
        entry.type(quoted.typedForm + ",")
        #expect(entry.contacts == [quoted])
    }

    @Test(arguments: [
        ("dana@example.com", true), ("dana", false), ("dana@example", false), ("@example.com", false),
        ("dana levi@example.com", false), ("dana@.com", false),
    ])
    func readsAddresses(text: String, isAddress: Bool) {
        #expect(Contact.isAddress(text) == isAddress)
    }
}
