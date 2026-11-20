import MailCore
import Testing

struct AppPresenceTests {
    @Test(arguments: [
        (AppLaunchState.active, PresencePolicy.suspends, AppPresence.attended),
        (.inactive, .suspends, .arriving),
        (.background, .suspends, .suspendable),
        (.active, .keepsRunning, .attended),
        (.inactive, .keepsRunning, .unattended),
        (.background, .keepsRunning, .unattended),
    ])
    func startsFromHowTheAppLaunched(state: AppLaunchState, policy: PresencePolicy, presence: AppPresence) {
        #expect(AppPresence(launchedIn: state, policy: policy) == presence)
    }

    /// Every state against every event on iOS, the way UIKit's notifications drive the app today: becoming active is
    /// always attended, entering the background always suspendable, and resigning only covers an attended app.
    @Test(arguments: [
        (AppPresence.arriving, PresenceEvent.becameActive, AppPresence.attended),
        (.attended, .becameActive, .attended),
        (.covered, .becameActive, .attended),
        (.suspendable, .becameActive, .attended),
        (.attended, .resignedActive, .covered),
        (.arriving, .resignedActive, .arriving),
        (.covered, .resignedActive, .covered),
        (.suspendable, .resignedActive, .suspendable),
        (.arriving, .enteredBackground, .suspendable),
        (.attended, .enteredBackground, .suspendable),
        (.covered, .enteredBackground, .suspendable),
        (.suspendable, .enteredBackground, .suspendable),
        (.suspendable, .enteringForeground, .arriving),
        (.arriving, .enteringForeground, .arriving),
        (.attended, .enteringForeground, .attended),
        (.covered, .enteringForeground, .covered),
    ])
    func suspendsOnIOS(from: AppPresence, event: PresenceEvent, to: AppPresence) {
        #expect(from.after(event, policy: .suspends) == to)
    }

    @Test(arguments: [
        (AppPresence.unattended, PresenceEvent.becameActive, AppPresence.attended),
        (.attended, .becameActive, .attended),
        (.attended, .resignedActive, .unattended),
        (.unattended, .resignedActive, .unattended),
        (.attended, .enteredBackground, .unattended),
        (.unattended, .enteredBackground, .unattended),
        (.unattended, .enteringForeground, .unattended),
        (.attended, .enteringForeground, .attended),
    ])
    func keepsRunningOnTheMac(from: AppPresence, event: PresenceEvent, to: AppPresence) {
        #expect(from.after(event, policy: .keepsRunning) == to)
    }

    @Test(arguments: [
        (AppPresence.attended, Duration?.some(.seconds(30))),
        (.covered, .seconds(30)),
        (.unattended, .seconds(5 * 60)),
        (.arriving, nil),
        (.suspendable, nil),
    ])
    func syncsMoreOftenWhileSomeoneLooks(presence: AppPresence, interval: Duration?) {
        #expect(presence.syncInterval == interval)
    }

    @Test(arguments: [
        (AppPresence.attended, true), (.covered, true), (.unattended, false), (.arriving, false), (.suspendable, false),
    ])
    func showsTheMailOnlyWhileTheReaderIsWithTheApp(presence: AppPresence, shows: Bool) {
        #expect(presence.showsMail == shows)
    }
}
