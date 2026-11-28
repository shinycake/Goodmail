import FieldDiagnostics
import Testing

/// The day's exits, by why the system ended the app, on screen and off.
struct ExitTallyTests {
    @Test func tallyEachReasonOnScreenAndOff() {
        let tallies = ExitTally.tallies(
            foreground: [.memoryLimit: 1, .watchdog: 2, .badAccess: 0],
            background: [.memoryLimit: 3, .lockedFile: 1, .memoryPressure: 5])
        #expect(
            tallies == [
                ExitTally(reason: .memoryLimit, foreground: 1, background: 3),
                ExitTally(reason: .memoryPressure, foreground: 0, background: 5),
                ExitTally(reason: .watchdog, foreground: 2, background: 0),
                ExitTally(reason: .lockedFile, foreground: 0, background: 1),
            ], "in the order of the reasons, without the ones that never happened")
        #expect(tallies.map(\.total) == [4, 5, 2, 1])
    }

    @Test func aDayWithNoExitsHasNoTallies() {
        #expect(ExitTally.tallies(foreground: [.watchdog: 0], background: [:]).isEmpty)
    }
}
