import Foundation
import MailCore
import Testing

/// The app holds one arrival, the newest, until a viewer can take it, opens a viewer window only when none is open or
/// coming, and never lets a message window take or drop one (D10).
struct ArrivalHoldTests {
    private let alert = Arrival.route(.thread(navigationRow("b").id, in: .inbox))
    private let later = Arrival.route(.thread(navigationRow("c").id, in: .inbox))
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func aViewerOpenTakesItAtOnce() {
        var hold = ArrivalHold()
        let windows = [WindowFacts(.message, isKey: true), WindowFacts(.viewer(reading: nil))]
        #expect(hold.arrive(alert, among: windows, onMac: true, now: start) == .give(alert, toWindow: 1))
    }

    @Test func atLaunchTheFirstViewerToFillTakesTheNewest() {
        var hold = ArrivalHold()
        #expect(hold.arrive(alert, among: [], onMac: true, now: start) == .none, "a window is coming up")
        #expect(hold.arrive(later, among: [WindowFacts(.opening)], onMac: true, now: start) == .none)
        #expect(hold.filled(.viewer(reading: nil), among: [], onMac: true, now: start) == .takeHere(later))
        #expect(hold.filled(.viewer(reading: nil), among: [], onMac: true, now: start) == .none, "taken once")
    }

    @Test func aMessageWindowRestoredFirstLeavesItForTheViewerComingUp() {
        var hold = ArrivalHold()
        _ = hold.arrive(alert, among: [], onMac: true, now: start)
        let windows = [WindowFacts(.message), WindowFacts(.opening)]
        #expect(hold.filled(.message, among: windows, onMac: true, now: start) == .none)
        #expect(hold.filled(.viewer(reading: nil), among: [], onMac: true, now: start) == .takeHere(alert))
    }

    @Test func aMessageWindowAloneOpensAViewerForIt() {
        var hold = ArrivalHold()
        _ = hold.arrive(alert, among: [], onMac: true, now: start)
        #expect(hold.filled(.message, among: [WindowFacts(.message)], onMac: true, now: start) == .openViewer)
    }

    @Test func otherWorkFillingHandsItOn() {
        var hold = ArrivalHold()
        hold.hold(.link(URL(string: "mailto:dana@example.com")!))
        let windows = [WindowFacts(.otherWork, isKey: true), WindowFacts(.viewer(reading: nil))]
        #expect(
            hold.filled(.otherWork, among: windows, onMac: true, now: start)
                == .give(.link(URL(string: "mailto:dana@example.com")!), toWindow: 1), "D13")
    }

    @Test func withEveryWindowClosedAMacOpensOneViewerForTheNewest() {
        var hold = ArrivalHold()
        _ = hold.filled(.viewer(reading: nil), among: [], onMac: true, now: start)
        #expect(hold.arrive(alert, among: [], onMac: true, now: start) == .openViewer)
        #expect(hold.arrive(later, among: [], onMac: true, now: start.addingTimeInterval(1)) == .none, "one window")
        #expect(hold.filled(.viewer(reading: nil), among: [], onMac: true, now: start) == .takeHere(later))
    }

    @Test func aViewerThatAppearsMeanwhileTakesTheNextArrival() {
        var hold = ArrivalHold()
        _ = hold.filled(.viewer(reading: nil), among: [], onMac: true, now: start)
        _ = hold.arrive(alert, among: [], onMac: true, now: start)
        let windows = [WindowFacts(.viewer(reading: nil), isKey: true)]
        #expect(hold.arrive(later, among: windows, onMac: true, now: start) == .give(later, toWindow: 0))
    }

    @Test func aViewerLongOverdueIsAskedForAgain() {
        var hold = ArrivalHold()
        _ = hold.filled(.viewer(reading: nil), among: [], onMac: true, now: start)
        _ = hold.arrive(alert, among: [], onMac: true, now: start)
        let overdue = start.addingTimeInterval(ArrivalHold.newViewerWait + 1)
        #expect(hold.arrive(later, among: [], onMac: true, now: overdue) == .openViewer)
    }

    @Test func aViewerThatCantOpenDropsIt() {
        var hold = ArrivalHold()
        _ = hold.filled(.viewer(reading: nil), among: [], onMac: true, now: start)
        _ = hold.arrive(alert, among: [], onMac: true, now: start)
        hold.newViewerFailed()
        #expect(hold.filled(.viewer(reading: nil), among: [], onMac: true, now: start) == .none)
    }

    @Test func onlyAMailWindowFillingMakesAClosedMacOpenOne() {
        var hold = ArrivalHold()
        _ = hold.filled(.otherWork, among: [], onMac: true, now: start)
        #expect(hold.arrive(alert, among: [], onMac: true, now: start) == .none, "a mail window is still coming")
    }

    @Test func aTouchDeviceWaitsForTheWindowTheSystemBringsUp() {
        var hold = ArrivalHold()
        _ = hold.filled(.viewer(reading: nil), among: [], onMac: false, now: start)
        #expect(hold.arrive(alert, among: [], onMac: false, now: start) == .none)
        #expect(hold.filled(.viewer(reading: nil), among: [], onMac: false, now: start) == .takeHere(alert))
    }

    @Test func withoutMailItIsDropped() {
        var hold = ArrivalHold()
        #expect(hold.arrive(alert, among: [WindowFacts(.noMail)], onMac: false, now: start) == .none)
        #expect(hold.filled(.viewer(reading: nil), among: [], onMac: false, now: start) == .none)
    }
}
