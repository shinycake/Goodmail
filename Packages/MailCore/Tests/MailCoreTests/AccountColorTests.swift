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
        let all = AccountColor.presets
        #expect(AccountColor.next(after: all) == all[0])
        #expect(AccountColor.next(after: all + [all[0]]) == all[1])
    }

    @Test func pickedColorsDoNotTakeAnOfferedOne() {
        let picked = AccountColor.custom(RGBColor(red: 0, green: 0, blue: 255))
        #expect(AccountColor.next(after: [picked]) == .blue)
    }

    @Test func redIsReservedForDestructiveActions() {
        #expect(AccountColor(rawValue: "red") == nil)
    }

    @Test(arguments: AccountColor.presets + [.custom(RGBColor(red: 18, green: 52, blue: 254))])
    func storedColorsReadBackAsThemselves(color: AccountColor) {
        #expect(AccountColor(rawValue: color.rawValue) == color)
    }

    @Test func offeredColorsKeepTheNamesEarlierBuildsStored() {
        #expect(
            AccountColor.presets.map(\.rawValue) == [
                "blue", "indigo", "purple", "pink", "orange", "yellow", "green", "mint", "teal", "cyan", "brown",
                "graphite",
            ])
    }

    @Test func pickedColorsAreStoredAsHex() {
        #expect(AccountColor.custom(RGBColor(red: 0x12, green: 0x34, blue: 0xFE)).rawValue == "#1234FE")
        #expect(AccountColor(rawValue: "#1234fe") == .custom(RGBColor(red: 0x12, green: 0x34, blue: 0xFE)))
    }
}
