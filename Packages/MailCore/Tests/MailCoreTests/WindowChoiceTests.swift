import MailCore
import Testing

/// An arrival from outside goes to a viewer already reading its conversation, else the key viewer, else any viewer;
/// with none, to a new viewer window, or to the one about to come up (D10).
struct WindowChoiceTests {
    private let thread = navigationRow("b").id
    private let other = navigationRow("a").id

    @Test func theViewerReadingTheConversationTakesIt() {
        let windows = [
            WindowFacts(.viewer(reading: other), isKey: true), WindowFacts(.viewer(reading: nil)),
            WindowFacts(.viewer(reading: thread)),
        ]
        #expect(WindowChoice.pick(reading: thread, among: windows, noWindow: .comesUp) == .window(2))
    }

    @Test func elseTheKeyViewer() {
        let windows = [
            WindowFacts(.message, isKey: false), WindowFacts(.viewer(reading: nil)),
            WindowFacts(.viewer(reading: other), isKey: true),
        ]
        #expect(WindowChoice.pick(reading: thread, among: windows, noWindow: .comesUp) == .window(2))
        #expect(WindowChoice.pick(reading: nil, among: windows, noWindow: .comesUp) == .window(2))
    }

    @Test func elseTheFrontViewer() {
        let windows = [
            WindowFacts(.otherWork, isKey: true), WindowFacts(.viewer(reading: other)),
            WindowFacts(.viewer(reading: nil)),
        ]
        #expect(WindowChoice.pick(reading: thread, among: windows, noWindow: .staysClosed) == .window(1))
    }

    @Test func aMessageWindowReadingItDoesntTakeIt() {
        let windows = [WindowFacts(.message, isKey: true), WindowFacts(.viewer(reading: nil))]
        #expect(WindowChoice.pick(reading: thread, among: windows, noWindow: .staysClosed) == .window(1))
    }

    @Test(arguments: [
        [WindowFacts(.message, isKey: true)], [WindowFacts(.otherWork, isKey: true), WindowFacts(.message)], [],
    ])
    func withNoViewerAMacOpensOne(windows: [WindowFacts]) {
        #expect(WindowChoice.pick(reading: thread, among: windows, noWindow: .staysClosed) == .newViewer)
    }

    @Test func withNoWindowTheOneComingUpTakesIt() {
        #expect(WindowChoice.pick(reading: thread, among: [], noWindow: .comesUp) == .wait)
    }

    @Test func aWindowStillOpeningTakesIt() {
        let windows = [WindowFacts(.message, isKey: true), WindowFacts(.opening)]
        #expect(WindowChoice.pick(reading: thread, among: windows, noWindow: .staysClosed) == .wait)
    }

    @Test func withoutMailThereIsNowhere() {
        #expect(WindowChoice.pick(reading: thread, among: [WindowFacts(.noMail)], noWindow: .comesUp) == .nowhere)
    }
}
