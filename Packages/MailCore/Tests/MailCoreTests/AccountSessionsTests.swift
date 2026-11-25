import Dispatch
import Synchronization
import Testing

@testable import MailCore

struct AccountSessionsTests {
    private let id = AccountID.generate()

    @Test func anAccountsSessionIsMadeOnceAndShared() throws {
        let signIns = StoredSignIns()
        let sessions = AccountSessions { try signIns.session(for: $0) }

        let first = try sessions.session(for: id)
        #expect(try sessions.session(for: id) === first)
        #expect(signIns.made == 1)
    }

    @Test func aNewSignInEndsTheOldSessionAndServesTheAccountFromThen() async throws {
        let sessions = AccountSessions { try StoredSignIns().session(for: $0) }
        let old = try sessions.session(for: id)
        let signedIn = FakeSession()

        await sessions.replace(id, with: signedIn)

        #expect(old.ended)
        #expect(!signedIn.ended)
        #expect(try sessions.session(for: id) === signedIn)
    }

    @Test func aChangedSignInIsReadAgainOnNextUse() async throws {
        let signIns = StoredSignIns()
        let sessions = AccountSessions { try signIns.session(for: $0) }
        let old = try sessions.session(for: id)

        await sessions.replace(id)

        #expect(old.ended)
        #expect(try sessions.session(for: id) !== old)
        #expect(signIns.made == 2)
    }

    @Test func aRemovedAccountGetsNoNewSessionUntilItIsAddedAgain() async throws {
        let signIns = StoredSignIns()
        let sessions = AccountSessions { try signIns.session(for: $0) }
        let old = try sessions.session(for: id)

        await sessions.remove(id)

        #expect(old.ended)
        #expect(throws: AccountSessions<FakeSession>.Failure.removed) { try sessions.session(for: id) }
        #expect(signIns.made == 1, "nothing reads the sign-in the removal is taking away")
        await sessions.replace(id)
        #expect(try sessions.session(for: id) !== old)
    }

    @Test func aSessionMadeFromASignInReplacedMeanwhileIsNotKept() async throws {
        let signIns = StoredSignIns(holdingFirstMake: true)
        let sessions = AccountSessions { try signIns.session(for: $0) }
        let signedIn = FakeSession()

        async let first = offThread { try sessions.session(for: id) }
        await signIns.firstMakeBegan()
        await sessions.replace(id, with: signedIn)
        signIns.finishFirstMake()

        #expect(try await first === signedIn)
        #expect(signIns.made == 1)
    }

    @Test func aSessionMadeFromASignInChangedMeanwhileIsMadeAgain() async throws {
        let signIns = StoredSignIns(holdingFirstMake: true)
        let sessions = AccountSessions { try signIns.session(for: $0) }

        async let first = offThread { try sessions.session(for: id) }
        await signIns.firstMakeBegan()
        await sessions.replace(id)
        signIns.finishFirstMake()

        let session = try await first
        #expect(signIns.made == 2, "made again from the new sign-in")
        #expect(try sessions.session(for: id) === session)
    }

    @Test func aMissingSignInThatWasStoredMeanwhileIsReadAgain() async throws {
        let signIns = StoredSignIns(holdingFirstMake: true, failingFirstMake: true)
        let sessions = AccountSessions { try signIns.session(for: $0) }

        async let first = offThread { try sessions.session(for: id) }
        await signIns.firstMakeBegan()
        await sessions.replace(id)
        signIns.finishFirstMake()

        _ = try await first
        #expect(signIns.made == 2)
    }

    @Test func theLiveSessionsAreTheOnesMadeAndNotEnded() async throws {
        let sessions = AccountSessions { try StoredSignIns().session(for: $0) }
        let other = AccountID.generate()
        let kept = try sessions.session(for: id)
        _ = try sessions.session(for: other)

        await sessions.remove(other)

        #expect(sessions.live.mapValues(ObjectIdentifier.init) == [id: ObjectIdentifier(kept)])
    }

    @Test func anAccountWithoutASignInHasNoSession() {
        let sessions = AccountSessions<FakeSession> { _ in throw StoredSignIns.Missing() }

        #expect(throws: StoredSignIns.Missing.self) { try sessions.session(for: id) }
        #expect(sessions.live.isEmpty)
    }
}

/// Runs `body` on a thread of its own, so it can wait inside a synchronous `make` while the test goes on.
private func offThread<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(with: Result { try body() }) }
    }
}

private final class FakeSession: LiveSession {
    private let state = Mutex(false)

    var ended: Bool { state.withLock { $0 } }

    func end() async {
        state.withLock { $0 = true }
    }
}

/// Makes a session from an account's stored sign-in, counting how often. With `holdingFirstMake`, the first make
/// waits for `finishFirstMake()`, as one reading a sign-in that changes meanwhile; with `failingFirstMake` it then
/// finds none.
private final class StoredSignIns: Sendable {
    struct Missing: Error {}

    private let holdingFirstMake: Bool
    private let failingFirstMake: Bool
    private let makes = Mutex(0)
    private let began = AsyncStream.makeStream(of: Void.self)
    private let finish = DispatchSemaphore(value: 0)

    init(holdingFirstMake: Bool = false, failingFirstMake: Bool = false) {
        self.holdingFirstMake = holdingFirstMake
        self.failingFirstMake = failingFirstMake
    }

    var made: Int { makes.withLock { $0 } }

    func firstMakeBegan() async {
        var began = began.stream.makeAsyncIterator()
        _ = await began.next()
    }

    func finishFirstMake() {
        finish.signal()
    }

    func session(for id: AccountID) throws -> FakeSession {
        let count = makes.withLock { made in
            made += 1
            return made
        }
        if count == 1, holdingFirstMake {
            began.continuation.yield()
            finish.wait()
            if failingFirstMake { throw Missing() }
        }
        return FakeSession()
    }
}
