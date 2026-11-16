import Testing

@testable import MailStore

struct DatabaseSuspensionTests {
    @Test func theForegroundNeverSuspends() {
        var suspension = DatabaseSuspension(phase: .foreground)
        #expect(!suspension.isSuspended)
        let work = suspension.begin()
        suspension.end(work)
        #expect(!suspension.isSuspended)
    }

    @Test func leavingTheForegroundWithNothingRunningSuspends() {
        var suspension = DatabaseSuspension(phase: .foreground)
        suspension.enter(.background)
        #expect(suspension.isSuspended)
        suspension.enter(.foreground)
        #expect(!suspension.isSuspended)
    }

    /// The build 1.0 (12) crash: a sync was mid-write as the reader left the app.
    @Test func workRunningAsTheAppLeavesKeepsTheDatabaseUntilItEnds() {
        var suspension = DatabaseSuspension(phase: .foreground)
        let sync = suspension.begin()
        suspension.enter(.background)
        #expect(!suspension.isSuspended)
        suspension.end(sync)
        #expect(suspension.isSuspended)
    }

    @Test func aBackgroundLaunchResumesForItsWorkOnly() {
        var suspension = DatabaseSuspension(phase: .background)
        #expect(suspension.isSuspended)
        let refresh = suspension.begin()
        let upload = suspension.begin()
        #expect(!suspension.isSuspended)
        suspension.end(refresh)
        #expect(!suspension.isSuspended)
        suspension.end(upload)
        #expect(suspension.isSuspended)
    }

    /// Work whose background time ran out is ended then, and again when it finally returns.
    @Test func endingWorkTwiceLeavesOtherWorkRunning() {
        var suspension = DatabaseSuspension(phase: .background)
        let expired = suspension.begin()
        let other = suspension.begin()
        suspension.end(expired)
        suspension.end(expired)
        #expect(!suspension.isSuspended)
        suspension.end(other)
        #expect(suspension.isSuspended)
    }
}
