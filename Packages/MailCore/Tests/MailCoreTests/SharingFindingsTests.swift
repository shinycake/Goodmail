import MailCore
import Testing

struct SharingFindingsTests {
    private let gmail = Account(id: AccountID(rawValue: "g"), email: "me@gmail.com", color: .blue, service: .gmail)
    private let outlook = Account(
        id: AccountID(rawValue: "o"), email: "me@outlook.com", color: .orange, service: .outlook)

    @Test func anAccountSignedInSinceThePassIsNoLongerOfferedBack() {
        let found = SharingFindings(restorable: [gmail], elsewhere: [gmail, outlook])

        // The reader signed in to Gmail from Welcome after a reinstall, before the next pass.
        #expect(found.restorable(besides: [gmail]).isEmpty)
        #expect(found.elsewhere(besides: [gmail]) == [outlook])
    }

    @Test func beforeAnyPassNothingIsFound() {
        let found = SharingFindings()

        #expect(found.restorable(besides: []).isEmpty)
        #expect(found.elsewhere(besides: []).isEmpty)
    }

    @Test func aRestoredAccountRemovedAgainIsntOfferedBackWithoutItsSignIn() {
        var found = SharingFindings(restorable: [gmail, outlook], elsewhere: [gmail])

        found.removed(gmail.id)

        #expect(found.restorable(besides: []) == [outlook])
        #expect(found.elsewhere(besides: []) == [gmail], "the other devices still have it")
    }

    @Test func anAccountRemovedSinceThePassIsFoundAgain() {
        let found = SharingFindings(restorable: [], elsewhere: [outlook])

        #expect(found.elsewhere(besides: [outlook]).isEmpty)
        #expect(found.elsewhere(besides: []) == [outlook], "it's elsewhere still, so it can be added back")
    }
}
