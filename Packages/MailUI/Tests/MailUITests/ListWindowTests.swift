import MailCore
import Testing

@testable import MailUI

/// How much of its mailbox a list reads: the newest, twice as many near their end, every thread while something
/// needs them all, and back again.
struct ListWindowTests {
    @Test func aWindowedListOpensOnItsFirstWindow() {
        #expect(ListWindow(windowed: true).asked == .newest(200))
        #expect(ListWindow(windowed: true, needs: [.filter]).asked == .whole, "a filter on at the start")
        #expect(ListWindow(windowed: false).asked == .whole)
    }

    @Test func itWidensOnlyWhileTheStoreHoldsMore() {
        var window = ListWindow(windowed: true)
        let atEnd = window.nearEnd(reach: .whole)
        #expect(!atEnd)
        #expect(window.asked == .newest(200))
        let widened = window.nearEnd(reach: .more)
        #expect(widened)
        #expect(window.asked == .newest(400))
    }

    @Test func aWholeListLetsGoOnlyOnceNothingNeedsIt() {
        var window = ListWindow(windowed: true)
        window.hold(.filter)
        window.hold(.selectAll)
        window.letGo(.filter, keeping: 0)
        #expect(window.asked == .whole)
        #expect(window.holds(.selectAll))
        #expect(!window.holds(.filter))
        window.letGo(.selectAll, keeping: 0)
        #expect(window.asked == .newest(200))
    }

    @Test func lettingGoKeepsTheDepthAskedForAndTheRowsAScrollReachesNext() {
        var window = ListWindow(windowed: true)
        window.hold(.selectAll)
        window.letGo(.selectAll, keeping: 1_000)
        #expect(window.asked == .newest(1_600), "enough for 1,000 threads and the next screenfuls")
    }

    @Test func lettingGoANeedNotHeldChangesNothing() {
        var window = ListWindow(windowed: true)
        window.hold(.filter)
        window.letGo(.selectAll, keeping: 5_000)
        #expect(window.asked == .whole)
    }

    @Test func aWholeListRemembersItsDeepestRowShownAndOnlyWhileWhole() {
        var window = ListWindow(windowed: true)
        window.shown(row: 150)
        #expect(window.deepestRowShown == nil)
        window.hold(.filter)
        window.shown(row: 40)
        window.shown(row: 12)
        #expect(window.deepestRowShown == 40)
        window.letGo(.filter, keeping: 0)
        #expect(window.deepestRowShown == nil)
        #expect(window.asked == .newest(200))
    }

    @Test func anotherCategoryStartsOnTheFirstWindowAndKeepsWhatNeedsTheWhole() {
        var window = ListWindow(windowed: true)
        _ = window.nearEnd(reach: .more)
        window.restart()
        #expect(window.asked == .newest(200))
        window.hold(.filter)
        window.restart()
        #expect(window.asked == .whole)
    }

    @Test func aListReadWholeIsAlwaysWhole() {
        var window = ListWindow(windowed: false)
        let widened = window.nearEnd(reach: .whole)
        #expect(!widened)
        window.letGo(.filter, keeping: 0)
        #expect(window.asked == .whole)
        #expect(window.isWhole(for: .everyThread))
        #expect(!window.holds(.everyThread), "nothing to let go")
    }
}
