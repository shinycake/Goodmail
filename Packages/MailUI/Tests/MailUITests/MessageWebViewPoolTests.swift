import Testing

@testable import MailUI

/// Web views are made ahead of the reader, so a message that opens finds one with its content process running.
@MainActor
struct MessageWebViewPoolTests {
    @Test func warmingUpMakesTheSpares() async {
        let pool = MessageWebViewPool()
        pool.warmUp()
        await pool.filled()
        #expect(pool.ready == MessageWebViewPool.spareCount)
    }

    @Test func aTakenSpareIsReplaced() async {
        let pool = MessageWebViewPool()
        pool.warmUp()
        await pool.filled()
        let taken = pool.take()
        #expect(pool.ready == MessageWebViewPool.spareCount - 1)

        await pool.filled()
        #expect(pool.ready == MessageWebViewPool.spareCount)
        #expect(pool.take() !== taken)
    }

    @Test func aViewIsMadeWhenNoSpareIsReady() {
        let pool = MessageWebViewPool()
        #expect(pool.take() !== pool.take())
    }
}
