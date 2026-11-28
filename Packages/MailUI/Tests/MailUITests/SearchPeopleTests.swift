import MailCore
import Testing

@testable import MailUI

/// Search offers the people what is typed names, found off the main actor, and only for the text the field holds.
@MainActor
struct SearchPeopleTests {
    private let dana = Contact(name: "Dana", address: "dana@example.com")
    private let danny = Contact(name: "Danny", address: "danny@example.com")

    /// What the lookups were asked for, in order.
    private actor Asked {
        private(set) var texts: [String] = []
        func record(_ text: String) { texts.append(text) }
    }

    /// Holds a lookup until `open()`, even once it is cancelled, as a slow database read would go on.
    private struct Gate: Sendable {
        private let opened: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation

        init() {
            (opened, continuation) = AsyncStream.makeStream()
        }

        func wait() async {
            // In a task of its own, which the lookup's cancelling doesn't reach.
            await Task { [opened] in for await _ in opened { return } }.value
        }

        func open() {
            continuation.finish()
        }
    }

    @Test func aSlowLookupForOlderTextOffersNobody() async throws {
        let gate = Gate()
        let (dana, danny) = (dana, danny)
        let people = SearchPeople { text in
            if text == "da" { await gate.wait() }
            return text == "da" ? [dana] : [danny]
        }
        var found: [String] = []
        let slow = try #require(people.lookUp("da") { found.append("da") })
        let fast = try #require(people.lookUp("dan") { found.append("dan") })
        await fast.value
        gate.open()
        await slow.value
        #expect(found == ["dan"])
        #expect(people.people(for: "da").isEmpty)
        #expect(people.people(for: "dan") == [danny])
    }

    @Test func returningToLookedUpTextOffersItsPeopleWithoutAskingAgain() async throws {
        let asked = Asked()
        let gate = Gate()
        let (dana, danny) = (dana, danny)
        let people = SearchPeople { text in
            await asked.record(text)
            if text == "dan" { await gate.wait() }
            return text == "dana" ? [dana] : [danny]
        }
        let first = try #require(people.lookUp("dana") {})
        await first.value
        #expect(people.people(for: "dana") == [dana])
        // Typed on and back before the newer lookup finished.
        let newer = try #require(people.lookUp("dan") {})
        #expect(people.lookUp("dana ") {} == nil, "already known")
        gate.open()
        await newer.value
        #expect(people.people(for: "dana") == [dana])
        #expect(await asked.texts == ["dana", "dan"])
    }

    @Test(arguments: ["", "   "])
    func blankTextOffersNobodyAndAsksNothing(_ typed: String) async {
        let asked = Asked()
        let dana = dana
        let people = SearchPeople { text in
            await asked.record(text)
            return [dana]
        }
        #expect(people.lookUp(typed) {} == nil)
        #expect(people.people(for: typed).isEmpty)
        #expect(await asked.texts.isEmpty)
    }
}
