import CoreGraphics
import Foundation
import MailCore
import Testing

@testable import MailUI

/// The empty Inbox's scene: which layout the space allows, which greeting the hour gets, how it arrived, how it comes
/// on and how it comes to rest. All of it is worked out from sizes and times.
struct InboxZeroTests {
    private let arrived = Date(timeIntervalSinceReferenceDate: 800_000_000)

    // MARK: Layout

    @Test(arguments: [
        (CGSize(width: 390, height: 640), false, InboxZeroLayout.full),
        (CGSize(width: 390, height: 560), false, .full),
        (CGSize(width: 390, height: 480), false, .short),
        (CGSize(width: 420, height: 300), false, .flanked),
        (CGSize(width: 300, height: 399), false, .bare),
        (CGSize(width: 390, height: 640), true, .bare),
    ])
    func theSpaceAndTheTextSizeChooseTheLayout(size: CGSize, accessibilityText: Bool, layout: InboxZeroLayout) {
        #expect(InboxZeroLayout(size: size, accessibilityText: accessibilityText) == layout)
    }

    @Test func onlyTheBareLayoutLeavesTheDoodlesOut() {
        #expect(InboxZeroLayout.full.hasDoodles)
        #expect(InboxZeroLayout.short.hasDoodles)
        #expect(InboxZeroLayout.flanked.hasDoodles)
        #expect(!InboxZeroLayout.bare.hasDoodles)
        #expect(InboxZeroLayout.bare.haloAbove == 0)
        #expect(InboxZeroLayout.full.pileWidth(wide: true) > InboxZeroLayout.full.pileWidth(wide: false))
    }

    // MARK: Greeting

    @Test(arguments: [
        (5, InboxZeroGreeting.morning), (11, .morning), (12, .afternoon), (16, .afternoon), (17, .evening),
        (21, .evening), (22, .night), (0, .night), (4, .night),
    ])
    func theGreetingFollowsTheHour(hour: Int, greeting: InboxZeroGreeting) {
        #expect(InboxZeroGreeting(hour: hour) == greeting)
    }

    // MARK: Arrival

    private static let t = ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "t")
    private static let other = ThreadSummary.ID(accountID: AccountID(rawValue: "a"), threadID: "other")

    private func inInbox(_ id: ThreadSummary.ID) -> ThreadSummary {
        ThreadSummary(
            id: id, subject: "", snippet: "", sender: Contact(name: nil, address: "x@example.com"), date: arrived,
            isUnread: true, messageCount: 1, labelIDs: [SystemLabel.inbox, SystemLabel.unread])
    }

    /// After the reader asked `request` of `asked` at `askedAt`, the rows of `left` left the Inbox at `leftAt`.
    private func removal(
        _ request: MailChange.Request = .action(.archive), of asked: [ThreadSummary.ID],
        at askedAt: ContinuousClock.Instant, then left: [ThreadSummary.ID], at leftAt: ContinuousClock.Instant
    ) -> RecentRemoval {
        var removal = RecentRemoval.none
        removal.rowsLeft(
            left.map(inInbox), answered: true, in: .inbox, asked: (MailChange(request, on: asked), askedAt), at: leftAt)
        return removal
    }

    @Test func emptiedByTheReaderAMomentAgoIsEarned() {
        let now = ContinuousClock.now
        let took = removal(of: [Self.t], at: now - .seconds(1), then: [Self.t], at: now)
        #expect(took == .took(at: now))
        #expect(InboxZeroArrival(onScreen: true, removal: took, at: now) == .earned)
        #expect(InboxZeroArrival(onScreen: true, removal: took, at: now + .seconds(2)) == .earned, "after a short page")
    }

    @Test func emptiedLongAfterTheReaderLastActedIsFound() {
        let now = ContinuousClock.now
        #expect(removal(of: [Self.t], at: now - .seconds(30), then: [Self.t], at: now) == .none)
        let took = removal(of: [Self.t], at: now, then: [Self.t], at: now)
        #expect(InboxZeroArrival(onScreen: true, removal: took, at: now + .seconds(30)) == .found, "a long page")
        #expect(InboxZeroArrival(onScreen: true, removal: .none, at: now) == .found)
    }

    @Test func emptiedBySyncJustAfterTheReaderActedIsFound() {
        let now = ContinuousClock.now
        #expect(removal(of: [Self.t], at: now, then: [Self.other], at: now) == .none, "not a row the reader asked away")
        // Starring or marking read leaves the row in the Inbox, so a sync that then takes it doesn't count.
        #expect(removal(.action(.star(true)), of: [Self.t], at: now, then: [Self.t], at: now) == .none)
        #expect(removal(.action(.markRead(true)), of: [Self.t], at: now, then: [Self.t], at: now) == .none)
        #expect(removal(.snooze, of: [Self.t], at: now, then: [Self.t], at: now) == .took(at: now))
    }

    @Test func rowsLeavingBeforeTheNewCategorysFirstAnswerIsInAreNotTheReaders() {
        let now = ContinuousClock.now
        var removal = RecentRemoval.switching
        // A row archived while the switch waits, as one archived just before it whose flight into a box ends now.
        let meanwhile = (MailChange(.action(.archive), on: [Self.t]), now)
        removal.rowsLeft([inInbox(Self.t)], answered: false, in: .inbox, asked: meanwhile, at: now)
        #expect(removal == .switching)
        // The last category's rows, the archived one among them, go as the new category's answer comes in.
        removal.rowsLeft(
            [inInbox(Self.t), inInbox(Self.other)], answered: true, in: .inbox, asked: meanwhile,
            at: now + .seconds(1))
        #expect(removal == .none)
        let since = (MailChange(.action(.archive), on: [Self.other]), now + .seconds(1))
        removal.rowsLeft([inInbox(Self.other)], answered: true, in: .inbox, asked: since, at: now + .seconds(2))
        #expect(removal == .took(at: now + .seconds(2)))
    }

    @Test func emptyBeforeTheListCameOnScreenIsSettled() {
        let now = ContinuousClock.now
        let took = removal(of: [Self.t], at: now, then: [Self.t], at: now)
        #expect(InboxZeroArrival(onScreen: false, removal: took, at: now) == .settled)
    }

    // MARK: Entrance

    @Test func anEarnedEntranceStartsEmptyAndSettlesInPlace() throws {
        let start = InboxZeroEntrance(arrival: .earned, elapsed: 0)
        #expect(start.pileOpacity == 0)
        #expect(start.fan == 0)
        #expect(start.text(appearingAt: InboxZeroEntrance.titleAppears) == 0)
        let reveal = try #require(start.reveal(from: .zero, reach: 200))
        #expect(reveal.progress(at: .zero) == 0)

        let settled = InboxZeroEntrance(arrival: .earned, elapsed: 2)
        #expect(settled.pileOpacity == 1)
        #expect(abs(settled.pileDrop) < 0.5)
        #expect(abs(settled.pileScale - 1) < 0.01)
        #expect(abs(settled.fan - 1) < 0.02)
        #expect(settled.text(appearingAt: InboxZeroEntrance.lineAppears) == 1)
        #expect(settled.reveal(from: .zero, reach: 200) == nil)
    }

    @Test func theFanSwingsPastTheIconsOnTheWayOpen() throws {
        let fans = stride(from: 0.0, to: 1.5, by: 0.01).map { InboxZeroEntrance(arrival: .earned, elapsed: $0).fan }
        let peak = try #require(fans.max())
        #expect(peak > 1.1)
        #expect(peak < 1.25)
    }

    @Test func theDoodlesNearestTheEnvelopesDrawFirst() throws {
        let reveal = try #require(InboxZeroEntrance(arrival: .earned, elapsed: 0.5).reveal(from: .zero, reach: 200))
        let near = reveal.progress(at: CGPoint(x: 20, y: 0))
        let far = reveal.progress(at: CGPoint(x: 200, y: 0))
        #expect(near > far)
        #expect(far >= 0)
    }

    @Test func aFoundSceneFadesIn() {
        #expect(InboxZeroEntrance(arrival: .found, elapsed: 0).opacity == 0)
        #expect(InboxZeroEntrance(arrival: .found, elapsed: 0.2).opacity > 0.5)
        #expect(InboxZeroEntrance(arrival: .found, elapsed: 1).opacity == 1)
        #expect(InboxZeroEntrance(arrival: .found, elapsed: 0).reveal(from: .zero, reach: 200) == nil)
    }

    @Test(arguments: [InboxZeroArrival.earned, .found, .settled])
    func withReduceMotionTheSceneIsInPlaceAtOnce(arrival: InboxZeroArrival) {
        let still = InboxZeroEntrance(arrival: arrival, elapsed: nil)
        #expect(still.opacity == 1)
        #expect(still.pileOpacity == 1)
        #expect(still.pileDrop == 0)
        #expect(still.pileScale == 1)
        #expect(still.fan == 1)
        #expect(still.text(appearingAt: InboxZeroEntrance.titleAppears) == 1)
        #expect(still.reveal(from: .zero, reach: 200) == nil)
    }

    // MARK: Coming to rest

    @Test func theDriftEasesInAfterArrivingAndOutBeforeSleep() {
        let wake = InboxZeroWake.awake(since: arrived, rampFrom: arrived)
        #expect(wake.energy(at: arrived) == 0)
        #expect(wake.energy(at: arrived + InboxZeroWake.rampTime) == 1)
        #expect(wake.energy(at: arrived + 20) == 1)
        let easing = wake.energy(at: arrived + 42.5)
        #expect(easing > 0 && easing < 1)
        #expect(wake.energy(at: arrived + InboxZeroWake.sleepsAfter) == 0)
        #expect(wake.sleepsAt == arrived + InboxZeroWake.sleepsAfter)
        #expect(InboxZeroWake.asleep.energy(at: arrived) == 0)
    }

    @Test func aTouchWhileAwakeKeepsItGoingWithoutAJolt() {
        let wake = InboxZeroWake.awake(since: arrived, rampFrom: nil).woken(at: arrived + 30)
        #expect(wake == .awake(since: arrived + 30, rampFrom: nil))
        #expect(wake.energy(at: arrived + 60) == 1)
    }

    @Test func aTouchOnASleepingSceneEasesItBackIn() {
        let wake = InboxZeroWake.asleep.woken(at: arrived)
        #expect(wake == .awake(since: arrived, rampFrom: arrived))
        #expect(wake.energy(at: arrived + 0.3) < 0.5)
    }

    /// The scene `wake` draws at `now`, with a plane passing every 16 s.
    private func scene(_ wake: InboxZeroWake, at now: Date) -> DoodleScene {
        DoodleScene(
            size: CGSize(width: 400, height: 400), pokes: [], clock: .running(now), rightToLeft: false,
            passInterval: 16, quietFrom: wake.quietFrom, passesFrom: wake.passesFrom)
    }

    /// A pass that set off a second before the game handed back would show up mid-flight, and one setting off two
    /// seconds after would follow the landing too closely.
    @Test(arguments: [-1.0, 2.0])
    func noPlanePassesJustAfterTheGameHandsBack(passSetsOff: TimeInterval) {
        let pass = (arrived.timeIntervalSinceReferenceDate / 16).rounded(.up) * 16
        let landed = Date(timeIntervalSinceReferenceDate: pass - passSetsOff)
        let wake = InboxZeroWake.asleep.woken(at: landed)
        #expect(scene(wake, at: landed + passSetsOff + 0.1).flights.isEmpty)
        for after in stride(from: 0.0, through: InboxZeroWake.passGap + DoodleScene.passTime, by: 0.05) {
            #expect(scene(wake, at: landed + after).flights.isEmpty)
        }
        // The next pass flies as usual.
        #expect(scene(wake, at: Date(timeIntervalSinceReferenceDate: pass + 16 + 0.5)).flights.count == 1)
    }

    @Test func aSleepingSceneHasNoPlaneInTheAir() {
        let pass = (arrived.timeIntervalSinceReferenceDate / 16).rounded(.up) * 16
        #expect(scene(.asleep, at: Date(timeIntervalSinceReferenceDate: pass + 0.5)).flights.isEmpty)
    }

    @Test func noPlaneSetsOffOnceTheSceneStartsToRest() {
        let wake = InboxZeroWake.awake(since: arrived, rampFrom: nil)
        let size = CGSize(width: 400, height: 400)
        // A moment when a plane would be passing, after the scene started coming to rest.
        let interval: TimeInterval = 16
        let pass = ((arrived + 41).timeIntervalSinceReferenceDate / interval).rounded(.up) * interval
        let now = Date(timeIntervalSinceReferenceDate: pass + 0.5)
        let resting = DoodleScene(
            size: size, pokes: [], clock: .running(now), rightToLeft: false, passInterval: interval,
            quietFrom: wake.quietFrom)
        #expect(resting.flights.isEmpty)
        let awake = DoodleScene(size: size, pokes: [], clock: .running(now), rightToLeft: false, passInterval: interval)
        #expect(awake.flights.count == 1)
    }

    @Test func atRestTheDoodlesHoldTheirPlaces() {
        let size = CGSize(width: 400, height: 400)
        let anchor = CGPoint(x: 0.25, y: 0.5)
        let still = DoodleScene(size: size, pokes: [], clock: .stopped, rightToLeft: false)
        let resting = DoodleScene(size: size, pokes: [], clock: .running(arrived), rightToLeft: false, energy: 0)
        #expect(resting.position(anchor: anchor, phase: 1.7) == still.position(anchor: anchor, phase: 1.7))
        #expect(resting.sway(phase: 1.7) == 0)
        #expect(resting.lift == 0)
        #expect(resting.fan == 1)
    }

    @Test func pokesLandAroundTheEnvelopesWhereverTheySit() {
        let focus = CGPoint(x: 200, y: 120)
        let scene = DoodleScene(
            size: CGSize(width: 400, height: 400), pokes: [DoodlePoke(offset: .zero, time: arrived, number: 0)],
            clock: .running(arrived), rightToLeft: false, focus: focus)
        #expect(scene.flights.first?.position == focus)
    }

    // MARK: Springs

    @Test func aSettlingSpringStartsAtRestAndEndsAtOne() {
        #expect(DoodleSpring.settle(-0.1, response: 0.5, damping: 0.6) == 0)
        #expect(DoodleSpring.settle(0, response: 0.5, damping: 0.6) == 0)
        #expect(abs(DoodleSpring.settle(3, response: 0.5, damping: 0.6) - 1) < 0.001)
    }

    // MARK: Words

    /// The singular leaves the count out of the words, so it must still pick the category by its position: taking the
    /// count for it crashed the app with one unread thread to point to.
    @Test(arguments: ["en", "he"], [1, 2]) @MainActor
    func theUnreadLineNamesTheCategoryForAnyCount(language: String, unread: Int) throws {
        let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"))
        let bundle = try #require(Bundle(path: path))
        let line = InboxZeroCopy.unread(in: InboxZeroPointer(category: .updates, unread: unread), bundle: bundle)
        #expect(line.contains(InboxCategory.updates.title))
        if unread > 1 { #expect(line.contains("\(unread)")) }
    }
}
