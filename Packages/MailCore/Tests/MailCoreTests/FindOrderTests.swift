import MailCore
import Testing

struct FindOrderTests {
    private typealias Attempt = FindOrder.Attempt

    @Test("A new search tries every letter from the top, none continuing a selection")
    func freshForward() {
        #expect(FindOrder.attempts(from: nil, count: 2, backwards: false) == [Attempt(view: 0), Attempt(view: 1)])
    }

    @Test("A new backwards search starts at the last letter")
    func freshBackwards() {
        #expect(FindOrder.attempts(from: nil, count: 2, backwards: true) == [Attempt(view: 1), Attempt(view: 0)])
    }

    @Test("Next goes on in the letter it is in, then the following ones, then wraps back to this one")
    func nextWraps() {
        #expect(
            FindOrder.attempts(from: 1, count: 3, backwards: false)
                == [Attempt(view: 1, continuesSelection: true), Attempt(view: 2), Attempt(view: 0), Attempt(view: 1)])
    }

    @Test("Previous goes the other way round")
    func previousWraps() {
        #expect(
            FindOrder.attempts(from: 1, count: 3, backwards: true)
                == [Attempt(view: 1, continuesSelection: true), Attempt(view: 0), Attempt(view: 2), Attempt(view: 1)])
    }

    @Test("One letter is searched on, then again from its start")
    func single() {
        #expect(
            FindOrder.attempts(from: 0, count: 1, backwards: false)
                == [Attempt(view: 0, continuesSelection: true), Attempt(view: 0)])
    }

    @Test("Nothing open, nothing to try; a stale position is ignored")
    func edges() {
        #expect(FindOrder.attempts(from: nil, count: 0, backwards: false).isEmpty)
        #expect(FindOrder.attempts(from: 5, count: 2, backwards: false) == [Attempt(view: 0), Attempt(view: 1)])
    }
}
