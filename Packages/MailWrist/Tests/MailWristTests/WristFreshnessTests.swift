import Foundation
import MailCore
import Testing

@testable import MailWrist

struct WristFreshnessTests {
    private static let earlier = Date(timeIntervalSince1970: 1_000)

    @Test(
        arguments: [
            (false, earlier, [AccountHealth.healthy], WristFreshness.current(checkedAt: earlier)),
            (true, earlier, [.healthy], .checking(lastChecked: earlier)),
            (true, nil, [.healthy], .checking(lastChecked: nil)),
            (false, nil, [], .checking(lastChecked: nil)),
            (false, earlier, [.faltering(.offline, since: earlier)], .current(checkedAt: earlier)),
            (false, earlier, [.healthy, .failing(.offline)], .behind(.offline, lastChecked: earlier)),
            (true, nil, [.failing(.timedOut)], .behind(.timedOut, lastChecked: nil)),
            (false, earlier, [.needsSignIn], .behind(.signInFailed, lastChecked: earlier)),
        ] as [(Bool, Date?, [AccountHealth], WristFreshness)])
    func theFooterFollowsTheChecks(
        checking: Bool, lastChecked: Date?, health: [AccountHealth], expected: WristFreshness
    ) {
        #expect(WristFreshness(checking: checking, lastChecked: lastChecked, health: health) == expected)
    }
}
