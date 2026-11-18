import CoreGraphics
import Foundation
import MailCore
import Testing

@testable import MailUI

/// The empty Inbox reaching past its list: the planes flying across the window's sky, the doodles beside the
/// envelopes in a low space and in the pane beside the list, and the touches they all share.
struct InboxZeroSkyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    /// An iPad's list beside the pane: the list from 0 to 420, the pane from 420 to 1180.
    private let sky = CGRect(x: 0, y: 0, width: 1180, height: 820)
    /// The ring's field in the list, in the window's coordinates.
    private var stage: InboxZeroStage {
        InboxZeroStage(field: CGRect(x: 10, y: 120, width: 400, height: 560), layout: .full, pileWidth: 240)
    }

    private func skyScene(pokes: [DoodlePoke], at time: Date, rightToLeft: Bool = false) -> DoodleScene {
        DoodleScene(
            sky: sky, stage: stage, pokes: pokes, wake: .awake(since: now, rampFrom: nil), clock: .running(time),
            rightToLeft: rightToLeft)
    }

    @Test func aPlaneFromTheEnvelopesFliesPastTheListAndLeavesByTheWindowsEdge() throws {
        let poke = DoodlePoke(offset: .zero, time: now, number: 0)
        let start = try #require(skyScene(pokes: [poke], at: now).flights.first)
        #expect(start.position == stage.center)
        let late = try #require(skyScene(pokes: [poke], at: now + DoodlePoke.flightTime * 0.97).flights.first)
        #expect(late.position.x > stage.field.maxX)
        #expect(late.position.x > sky.maxX - 120)
    }

    @Test func inARightToLeftLanguageItLeavesByTheOtherEdge() throws {
        let poke = DoodlePoke(offset: .zero, time: now, number: 0)
        let late = try #require(
            skyScene(pokes: [poke], at: now + DoodlePoke.flightTime * 0.97, rightToLeft: true).flights.first)
        #expect(late.position.x < 120)
    }

    @Test func aPlanePassingByItselfComesInLowAcrossTheField() throws {
        let pass = (now.timeIntervalSinceReferenceDate / InboxZeroSky.passEvery).rounded(.up) * InboxZeroSky.passEvery
        let scene = skyScene(pokes: [], at: Date(timeIntervalSinceReferenceDate: pass + 0.01))
        let plane = try #require(scene.flights.first)
        #expect(plane.position.x < sky.minX)
        #expect(abs(plane.position.y - (stage.field.minY + stage.field.height * 0.8)) < 2)
    }

    @Test func planesInTheAirCarryOnAndNoneFollowThem() {
        let pass = (now.timeIntervalSinceReferenceDate / InboxZeroSky.passEvery).rounded(.up) * InboxZeroSky.passEvery
        let tapped = Date(timeIntervalSinceReferenceDate: pass - 1)
        let poke = DoodlePoke(offset: .zero, time: tapped - 0.5, number: 0)
        let carried = skyScene(pokes: [poke], at: tapped).carriedOn(by: 1.2)
        // The poke's plane is still up; the pass that would set off a second after the tap never does.
        #expect(carried.flights.count == 1)
        #expect(carried.flights == skyScene(pokes: [poke], at: tapped + 1.2).flights.filter { $0.number == 0 })
    }

    @Test func theFlanksKeepClearOfTheWords() {
        for doodle in Doodle.inboxZeroFlanks {
            #expect(doodle.anchor.x <= 0.17 || doodle.anchor.x >= 0.83)
        }
        #expect(!InboxZeroLayout.flanked.isRinged)
        #expect(InboxZeroLayout.flanked.doodles.count == Doodle.inboxZeroFlanks.count)
        #expect(InboxZeroLayout.full.doodles.count == Doodle.inboxZero.count)
    }

    @Test func flankedDoodlesFlyPlanesButAreNotTheRingTheGameTakesOver() {
        let flanked = InboxZeroStage(
            field: CGRect(x: 0, y: 0, width: 420, height: 160), layout: .flanked, pileWidth: 132)
        #expect(flanked.layout.hasDoodles)
        #expect(!flanked.isDecorated)
        let bare = InboxZeroStage(field: CGRect(x: 0, y: 0, width: 300, height: 160), layout: .bare, pileWidth: 132)
        #expect(!bare.layout.hasDoodles)
    }

    @Test func thePanesDoodlesThinOutAwayFromTheList() {
        let size = CGSize(width: 900, height: 700)
        let pane = DoodleScene(size: size, pokes: [], clock: .stopped, rightToLeft: false, widest: .infinity)
        let xs = Doodle.inboxZeroBeyond.enumerated().map { pane.pose(of: $1, at: $0).position.x }
        let near = xs.filter { $0 < 300 }.count
        let far = xs.filter { $0 >= 600 }.count
        #expect(near >= 2 * far)
        #expect(far > 0)
    }

    @Test func aPlaneOnALongRunIsPastTheEdgeBeforeItFades() {
        let poke = DoodlePoke(offset: .zero, time: now, number: 0)
        let fading = stride(from: 0.5, through: 1.0, by: 0.01).compactMap {
            skyScene(pokes: [poke], at: now + DoodlePoke.flightTime * $0).flights.first
        }
        .filter { $0.opacity < 1 }
        #expect(fading.count > 5)
        for plane in fading { #expect(plane.position.x > sky.maxX) }
    }

    @Test func aTouchOnTheListPushesThePanesDoodlesToo() {
        // The pane from the window's 420, so the envelopes sit 210 points beyond its leading edge.
        let focus = CGPoint(x: -210, y: 300)
        let size = CGSize(width: 760, height: 700)
        let anchor = CGPoint(x: 0.07, y: 0.4)
        let poke = DoodlePoke(offset: CGSize(width: 180, height: 0), time: now, number: 0)
        let touched = DoodleScene(
            size: size, pokes: [poke], clock: .running(now + 0.15), rightToLeft: false, focus: focus, energy: 0,
            widest: .infinity)
        let calm = DoodleScene(
            size: size, pokes: [], clock: .running(now + 0.15), rightToLeft: false, focus: focus, energy: 0,
            widest: .infinity)
        #expect(touched.position(anchor: anchor, phase: 0).x > calm.position(anchor: anchor, phase: 0).x)
    }

    @Test func thePanesDoodlesDrawInAfterTheRingStarts() throws {
        let entrance = InboxZeroEntrance(arrival: .earned, elapsed: InboxZeroEntrance.doodlesDraw + 0.1)
        let reveal = try #require(entrance.revealBeyond(from: .zero, reach: 800))
        #expect(reveal.progress(at: CGPoint(x: 100, y: 0)) == 0)
        let later = try #require(
            InboxZeroEntrance(arrival: .earned, elapsed: InboxZeroEntrance.beyondDraws + 0.3)
                .revealBeyond(from: .zero, reach: 800))
        #expect(later.progress(at: CGPoint(x: 100, y: 0)) > later.progress(at: CGPoint(x: 700, y: 0)))
        #expect(InboxZeroEntrance(arrival: .found, elapsed: 0.1).revealBeyond(from: .zero, reach: 800) == nil)
    }

    // MARK: Sharing the scene

    @Test @MainActor func anEarnedInboxSeesAPlaneOffAndAFoundOneDoesNot() {
        let model = InboxZeroModel()
        model.arrive(InboxZeroShowing(arrival: .earned, arrivedAt: now))
        #expect(model.pokes.count == 1)
        #expect(model.wake != .asleep)
        model.arrive(InboxZeroShowing(arrival: .found, arrivedAt: now))
        #expect(model.pokes.isEmpty)
        model.arrive(
            InboxZeroShowing(
                arrival: .earned, arrivedAt: now, pointing: InboxZeroPointer(category: .updates, unread: 2)))
        #expect(model.pokes.isEmpty)
    }

    @Test @MainActor func anInboxThatEmptiesDuringTheGameWaitsAsleep() {
        let model = InboxZeroModel()
        model.setPlaying(true)
        model.arrive(InboxZeroShowing(arrival: .earned, arrivedAt: now))
        #expect(model.wake == .asleep)
        #expect(model.pokes.isEmpty)
        model.setPlaying(false)
        #expect(model.wake != .asleep)
    }

    @Test @MainActor func aTouchDuringTheGameLandsNowhere() {
        let model = InboxZeroModel()
        model.arrive(InboxZeroShowing(arrival: .found, arrivedAt: now))
        model.setPlaying(true)
        model.poke(at: .zero)
        model.wakeUp()
        #expect(model.state == .game(InboxZeroShowing(arrival: .found, arrivedAt: now)))
    }

    @Test @MainActor func mailArrivingTakesTheTouchesAndTheDriftWithTheScene() {
        let model = InboxZeroModel()
        model.arrive(InboxZeroShowing(arrival: .earned, arrivedAt: now))
        model.leave()
        #expect(model.state == .away)
        #expect(model.pokes.isEmpty)
        #expect(model.wake == .asleep)
    }

    @Test @MainActor func mailThatArrivesDuringTheGameIsWaitingWhenItEnds() {
        let model = InboxZeroModel()
        model.arrive(InboxZeroShowing(arrival: .found, arrivedAt: now))
        model.setPlaying(true)
        model.leave()
        #expect(model.state == .game(nil))
        model.setPlaying(false)
        #expect(model.state == .away)
    }

    @Test @MainActor func onlyTheListOnShowLendsTheSkyItsScene() {
        let sky = InboxZeroSky()
        let old = InboxZeroModel()
        let new = InboxZeroModel()
        sky.attach(old)
        sky.attach(new)
        sky.detach(old)
        #expect(sky.inbox === new)
        sky.detach(new)
        #expect(sky.inbox == nil)
    }

    @Test @MainActor func aListThatLeftItsWindowStillTakesItsSceneBack() {
        let sky = InboxZeroSky()
        let model = InboxZeroModel()
        var loan = InboxZeroLoan()
        loan.update(model, found: sky, shows: true)
        #expect(sky.inbox === model)
        // Replaced in its column by a list with no scene, it is out of the stack and finds no sky.
        loan.update(model, found: nil, shows: false)
        #expect(sky.inbox == nil)
    }

    @Test @MainActor func aListMovedToAnotherWindowTakesItsSceneFromTheFirstSky() {
        let first = InboxZeroSky()
        let second = InboxZeroSky()
        let model = InboxZeroModel()
        var loan = InboxZeroLoan()
        loan.update(model, found: first, shows: true)
        loan.update(model, found: second, shows: true)
        #expect(first.inbox == nil)
        #expect(second.inbox === model)
    }

    @Test @MainActor func noPlaneFliesWhileTheGameHasTheEnvelopes() {
        let sky = InboxZeroSky()
        sky.frame = self.sky
        let model = InboxZeroModel()
        model.onScreen = stage
        model.arrive(InboxZeroShowing(arrival: .found, arrivedAt: now))
        sky.attach(model)
        #expect(sky.flights(at: now, rightToLeft: false) != nil)
        model.setPlaying(true)
        #expect(sky.flights(at: now, rightToLeft: false) == nil)
    }
}
