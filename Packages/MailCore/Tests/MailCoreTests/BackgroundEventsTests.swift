import Testing

@testable import MailCore

struct BackgroundEventsTests {
    @Test func theHandlerWaitsUntilEveryEventIsDeliveredAndTakenIn() {
        var events = BackgroundEvents<String>()

        events.receive("woke")
        #expect(events.due(allTakenIn: true).isEmpty, "iOS is still delivering")
        events.delivered()
        #expect(events.due(allTakenIn: false).isEmpty, "an outcome is still being taken in")
        #expect(events.due(allTakenIn: true) == ["woke"])
    }

    @Test func eventsTakenInBeforeTheHandlerComeAreAnsweredAsSoonAsItDoes() {
        var events = BackgroundEvents<String>()

        events.delivered()
        #expect(events.due(allTakenIn: true).isEmpty)
        events.receive("woke")

        #expect(events.due(allTakenIn: true) == ["woke"])
    }

    @Test func aHandlerIsCalledOnceAndTheNextWakeWaitsForItsOwnEvents() {
        var events = BackgroundEvents<String>()
        events.receive("first")
        events.delivered()
        #expect(events.due(allTakenIn: true) == ["first"])

        #expect(events.due(allTakenIn: true).isEmpty)
        events.receive("second")
        #expect(events.due(allTakenIn: true).isEmpty)
        events.delivered()
        #expect(events.due(allTakenIn: true) == ["second"])
    }

    @Test func everyHandlerGivenForOneDeliveryIsCalled() {
        var events = BackgroundEvents<String>()
        events.receive("first")
        events.receive("second")
        events.delivered()

        #expect(events.due(allTakenIn: true) == ["first", "second"])
    }
}
