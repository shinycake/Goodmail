import MailCore
import Testing

struct WatchRestartsTests {
    @Test func leavesAnEndedWatchEndedWhereTheAppIsSuspended() {
        var restarts = WatchRestarts(policy: .suspends)
        #expect(restarts.delay(afterRunning: .seconds(1)) == nil)
        #expect(restarts.delay(afterRunning: .seconds(2 * 60 * 60)) == nil)
    }

    @Test func waitsLongerAfterEachQuickEndUpToAnHour() {
        var restarts = WatchRestarts(policy: .keepsRunning)
        let delays = (0..<9).map { _ in restarts.delay(afterRunning: .seconds(1)) }
        #expect(delays == [1, 2, 4, 8, 16, 32, 60, 60, 60].map { Duration.seconds($0 * 60) })
    }

    @Test func startsOverAfterAWatchThatLasted() {
        var restarts = WatchRestarts(policy: .keepsRunning)
        _ = restarts.delay(afterRunning: .seconds(1))
        _ = restarts.delay(afterRunning: .seconds(1))
        #expect(restarts.delay(afterRunning: .seconds(60 * 60)) == .seconds(60))
        #expect(restarts.delay(afterRunning: .seconds(1)) == .seconds(2 * 60))
    }
}

struct OversleepTests {
    @Test(arguments: [
        (Duration.seconds(30), Duration.seconds(30), false),
        (.seconds(30), .seconds(5), false),
        // A late timer, as under App Nap, is not a sleep.
        (.seconds(30), .seconds(85), false),
        (.seconds(30), .seconds(95), true),
        (.seconds(300), .seconds(590), false),
        (.seconds(300), .seconds(610), true),
        (.seconds(300), .seconds(8 * 60 * 60), true),
    ])
    func tellsASleepFromALateTimer(asked: Duration, took: Duration, slept: Bool) {
        #expect(Oversleep.meansTheDeviceSlept(asked: asked, took: took) == slept)
    }
}
