import MailCore
import Testing

struct CardDragTests {
    @Test(arguments: [
        (translation: 0.0, progress: 0.0),
        (translation: 150, progress: 0.5),
        (translation: 300, progress: 1),
        // Past either end the card stays at that end.
        (translation: -40, progress: 0),
        (translation: 420, progress: 1),
    ])
    func progressFollowsTheFinger(translation: Double, progress: Double) {
        #expect(CardDrag(distance: 300).progress(translation: translation) == progress)
    }

    @Test func aDistanceOfNothingIsAlreadyThere() {
        #expect(CardDrag(distance: 0).progress(translation: 10) == 1)
    }

    @Test func velocityIsMeasuredInTrips() {
        #expect(CardDrag(distance: 400).velocity(points: 800) == 2)
    }

    @Test(arguments: [
        // Let go while moving: the finger's speed counts.
        (velocity: 1.2, stillFor: 0.02, release: 1.2),
        // Held still before letting go: UIKit still reports the last speed it saw, but the finger had stopped.
        (velocity: 1.2, stillFor: CardDrag.stillness, release: 0),
        (velocity: -0.6, stillFor: 0.3, release: 0),
    ])
    func aFingerHeldStillLetsGoWithoutSpeed(velocity: Double, stillFor: Double, release: Double) {
        #expect(CardDrag.releaseVelocity(velocity, stillFor: stillFor) == release)
    }

    @Test(arguments: [
        // Let go slowly: whichever end is nearer.
        (progress: 0.6, velocity: 0.0, settle: CardDrag.Settle.arrive),
        (progress: 0.4, velocity: 0.0, settle: .goBack),
        // A flick carries it, even from near the start.
        (progress: 0.1, velocity: 2.5, settle: .arrive),
        (progress: 0.9, velocity: -2.5, settle: .goBack),
        // A quick flick a short way, as measured on the simulator, still carries the card.
        (progress: 0.23, velocity: 0.59, settle: .arrive),
        // A gentle push counts for where it was heading.
        (progress: 0.4, velocity: 0.8, settle: .arrive),
        (progress: 0.6, velocity: -0.8, settle: .goBack),
    ])
    func lettingGoSettlesWhereTheMotionLeads(progress: Double, velocity: Double, settle: CardDrag.Settle) {
        #expect(CardDrag.settle(progress: progress, velocity: velocity) == settle)
    }

    @Test func theSpringPicksUpTheFingersSpeedTowardWhereItSettles() {
        // Half the way left, moving one trip a second: two remaining distances a second.
        #expect(CardDrag.springVelocity(progress: 0.5, velocity: 1, settle: .arrive) == 2)
        #expect(CardDrag.springVelocity(progress: 0.5, velocity: -1, settle: .goBack) == 2)
    }

    @Test func aFingerMovingAwayFromWhereItSettlesGivesTheSpringNoPush() {
        #expect(CardDrag.springVelocity(progress: 0.7, velocity: -0.2, settle: .arrive) == 0)
    }

    @Test func theSpringsPushIsCapped() {
        #expect(
            CardDrag.springVelocity(progress: 0.99, velocity: 30, settle: .arrive) == CardDrag.maximumSpringVelocity)
    }

    @Test(arguments: [
        (progress: 0.25, settle: CardDrag.Settle.arrive, factor: 0.75),
        (progress: 0.25, settle: .goBack, factor: 0.3),
        (progress: 1, settle: .arrive, factor: 0.3),
    ])
    func theSpringTakesLessTimeTheLessIsLeft(progress: Double, settle: CardDrag.Settle, factor: Double) {
        #expect(CardDrag.durationFactor(progress: progress, settle: settle) == factor)
    }
}
