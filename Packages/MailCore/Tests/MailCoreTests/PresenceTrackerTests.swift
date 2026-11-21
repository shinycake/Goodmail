import Foundation
import MailCore
import Testing

/// The tracker follows the lifecycle notifications it is given, as a Mac app gets AppKit's.
@MainActor
struct PresenceTrackerTests {
    private let center = NotificationCenter()

    private func post(_ source: PresenceSource) {
        center.post(name: source.name, object: nil)
    }

    private var becameActive: PresenceSource { PresenceSource.appKit.first { $0.event == .becameActive }! }
    private var resignedActive: PresenceSource { PresenceSource.appKit.first { $0.event == .resignedActive }! }

    @Test func aMacAppGoesUnattendedWhenTheReaderMovesToAnotherAppAndBack() {
        let tracker = PresenceTracker(
            launchedIn: .active, policy: .keepsRunning, sources: PresenceSource.appKit, center: center)
        var changes: [AppPresence] = []
        tracker.follow { _, new in changes.append(new) }

        post(resignedActive)
        #expect(tracker.presence == .unattended)
        post(becameActive)
        #expect(tracker.presence == .attended)
        #expect(changes == [.unattended, .attended], "each coming back is news to the followers, as on iOS")
    }

    @Test func appKitsNotificationsAreTheOnesAMacAppPosts() {
        #expect(
            PresenceSource.appKit.map(\.name.rawValue).sorted()
                == ["NSApplicationDidBecomeActiveNotification", "NSApplicationDidResignActiveNotification"])
    }

    @Test func newsThatChangesNothingTellsNoFollower() {
        let tracker = PresenceTracker(
            launchedIn: .active, policy: .keepsRunning, sources: PresenceSource.appKit, center: center)
        var told = 0
        tracker.follow { _, _ in told += 1 }
        post(becameActive)
        #expect(told == 0)
    }

    @Test func onlyAMacRenewsPushOnATimer() throws {
        let interval = try #require(PresencePolicy.keepsRunning.pushRenewalInterval)
        #expect(
            interval < .seconds(24 * 60 * 60), "well inside the day an Outlook subscription runs before it falls due")
        #expect(PresencePolicy.suspends.pushRenewalInterval == nil)
    }
}
