import MailCore
import Testing

@testable import MailUI

struct RecipientSuggesterTests {
    private actor FakeAddressBook: DeviceContacts {
        var access: ContactsAccess
        /// What the user answers when asked.
        let answer: ContactsAccess
        let cards: [Contact]
        private(set) var asked = 0
        private(set) var read = 0

        init(access: ContactsAccess, answer: ContactsAccess = .denied, cards: [Contact] = []) {
            self.access = access
            self.answer = answer
            self.cards = cards
        }

        func requestAccess() async -> ContactsAccess {
            asked += 1
            access = answer
            return answer
        }

        func people() async throws -> [Contact] {
            read += 1
            return cards
        }
    }

    private let dana = Contact(name: "Dana Levi", address: "dana@example.com")
    private let noa = Contact(name: "Noa Katz", address: "noa@work.example")
    private let dan = Contact(name: "Dan Aviv", address: "dan@home.example")

    private func suggester(_ book: FakeAddressBook, writtenIn: [Contact] = []) -> RecipientSuggester {
        RecipientSuggester(writtenIn: { _ in writtenIn }, addressBook: book)
    }

    private struct Unreadable: Error {}

    @Test func deviceContactsFollowThePeopleWhoWroteIn() async {
        let book = FakeAddressBook(access: .authorized, cards: [dan, dana, noa])
        let found = await suggester(book, writtenIn: [noa]).suggestions(for: "d")
        #expect(found == [noa, dan, dana], "who wrote in first, then the device by name")
    }

    @Test func matchesAddressesNamesAndWordsOfNames() async {
        let book = FakeAddressBook(access: .authorized, cards: [dana, noa, dan])
        let suggester = suggester(book)
        #expect(await suggester.suggestions(for: "noa@w") == [noa])
        #expect(await suggester.suggestions(for: "LEV") == [dana], "a word of the name, any case")
        #expect(await suggester.suggestions(for: "Dan A") == [dan], "spanning words")
        #expect(await suggester.suggestions(for: "vi").isEmpty, "not from the middle of a word")
    }

    @Test func oneAddressIsOneSuggestionWithTheDevicesName() async {
        let mail = Contact(name: "dana", address: "Dana@Example.com")
        let twin = Contact(name: "Dana L.", address: "dana@example.com")
        let book = FakeAddressBook(access: .authorized, cards: [dana, twin])
        let found = await suggester(book, writtenIn: [mail]).suggestions(for: "dana")
        #expect(found == [Contact(name: "Dana Levi", address: "Dana@Example.com")])
    }

    @Test func aDevicesNameFillsInWhereMailHasNone() async {
        let bare = Contact(name: nil, address: "noa@work.example")
        let book = FakeAddressBook(access: .authorized, cards: [noa])
        #expect(await suggester(book, writtenIn: [bare]).suggestions(for: "n") == [noa])
    }

    @Test func keepsTheNameOnMailWhenTheCardHasNone() async {
        let nameless = Contact(name: nil, address: dana.address)
        let book = FakeAddressBook(access: .authorized, cards: [nameless])
        #expect(await suggester(book, writtenIn: [dana]).suggestions(for: "dana") == [dana])
    }

    @Test func theLimitCutsTheDeviceContactsFirst() async {
        let book = FakeAddressBook(access: .authorized, cards: [dan, dana])
        let found = await suggester(book, writtenIn: [noa]).suggestions(for: "d", limit: 2)
        #expect(found == [noa, dan])
    }

    @Test func asksOnTheFirstLookupAndOnlyThen() async {
        let book = FakeAddressBook(access: .notDetermined, answer: .authorized, cards: [dana])
        let suggester = suggester(book)
        #expect(await suggester.suggestions(for: "da") == [dana])
        #expect(await suggester.suggestions(for: "dan") == [dana])
        #expect(await book.asked == 1)
    }

    @Test func limitedAccessReadsWhatWasShared() async {
        let book = FakeAddressBook(access: .notDetermined, answer: .limited, cards: [dana])
        #expect(await suggester(book).suggestions(for: "da") == [dana])
    }

    @Test(arguments: [ContactsAccess.denied, .notDetermined])
    func withoutAccessOnlyMailSuggests(refused: ContactsAccess) async {
        let book = FakeAddressBook(access: refused, answer: .denied, cards: [dana])
        #expect(await suggester(book, writtenIn: [noa]).suggestions(for: "n") == [noa])
        #expect(await book.read == 0)
    }

    @Test func deniedIsNeverAskedAgain() async {
        let book = FakeAddressBook(access: .denied, answer: .authorized, cards: [dana])
        #expect(await suggester(book).suggestions(for: "da").isEmpty)
        #expect(await book.asked == 0)
    }

    @Test func theBookIsReadOnceForAllTheKeystrokes() async {
        let book = FakeAddressBook(access: .authorized, cards: [dana, dan])
        let suggester = suggester(book)
        #expect(await suggester.suggestions(for: "d") == [dan, dana])
        #expect(await suggester.suggestions(for: "dana") == [dana])
        #expect(await book.read == 1)
    }

    @Test func aDatabaseThatFailsStillLeavesTheDevicesPeople() async {
        let book = FakeAddressBook(access: .authorized, cards: [dana])
        let suggester = RecipientSuggester(writtenIn: { _ in throw Unreadable() }, addressBook: book)
        #expect(await suggester.suggestions(for: "da") == [dana])
    }
}
