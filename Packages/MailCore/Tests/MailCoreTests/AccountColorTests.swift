import Testing

@testable import MailCore

struct AccountColorTests {
    @Test func firstAccountGetsTheFirstColor() {
        #expect(AccountColor.next(after: []) == .blue)
    }

    @Test func skipsColorsAlreadyInUse() {
        #expect(AccountColor.next(after: [.blue, .purple]) == .indigo)
    }

    @Test func cyclesOnceEveryColorIsTaken() {
        let all = AccountColor.allCases
        #expect(AccountColor.next(after: all) == all[0])
        #expect(AccountColor.next(after: all + [all[0]]) == all[1])
    }

    @Test func redIsReservedForDestructiveActions() {
        #expect(AccountColor(rawValue: "red") == nil)
    }
}
