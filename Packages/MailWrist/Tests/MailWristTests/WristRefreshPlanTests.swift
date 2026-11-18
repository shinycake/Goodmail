import Foundation
import Testing

@testable import MailWrist

struct WristRefreshPlanTests {
    private static let run = Date(timeIntervalSince1970: 10_000)

    @Test(
        arguments: [
            (false, run.addingTimeInterval(15 * 60)),
            (true, nil),
        ] as [(Bool, Date?)])
    func theNextCheckIsAQuarterHourOnUnlessPowerIsLow(lowPower: Bool, expected: Date?) {
        #expect(WristRefreshPlan.next(after: Self.run, lowPower: lowPower) == expected)
    }
}
