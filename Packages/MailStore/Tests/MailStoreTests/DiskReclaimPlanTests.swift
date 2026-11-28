import Testing

@testable import MailStore

/// `DiskReclaim.plan`: what a reclaim does for each kind of file, reason and room on the volume (ADR-044).
struct DiskReclaimPlanTests {
    private static let page: Int64 = 4096
    private static let megabyte: Int64 = 1 << 20

    /// A file of `liveMB` and `freeMB`, with `tailMB` past its last page and a log of `walMB`.
    private static func usage(
        _ mode: DiskUsage.Mode, liveMB: Int64, freeMB: Int64, tailMB: Int64 = 0, walMB: Int64 = 0
    ) -> DiskUsage {
        DiskUsage(
            fileBytes: (liveMB + freeMB + tailMB) * megabyte, walBytes: walMB * megabyte,
            freeBytes: freeMB * megabyte, liveBytes: liveMB * megabyte, pageSize: page, mode: mode)
    }

    struct Case: Sendable, CustomTestStringConvertible {
        let testDescription: String
        let usage: DiskUsage
        let reason: DiskReclaim.Reason
        var volumeFreeMB: Int64 = 10_000
        var mayConvert = true
        let plan: DiskReclaim
    }

    static let cases: [Case] = [
        Case(
            testDescription: "after a trim, free pages past the threshold go back",
            usage: usage(.incremental, liveMB: 100, freeMB: 5), reason: .afterTrim,
            plan: .release(pages: 5 * megabyte / page)),
        Case(
            testDescription: "after a trim, a few free pages stay",
            usage: usage(.incremental, liveMB: 100, freeMB: 1), reason: .afterTrim, plan: .nothing),
        Case(
            testDescription: "when the reader asks, every free page goes back",
            usage: usage(.incremental, liveMB: 100, freeMB: 1), reason: .readerAsked,
            plan: .release(pages: megabyte / page)),
        Case(
            testDescription: "with no free pages there is nothing to give back",
            usage: usage(.incremental, liveMB: 100, freeMB: 0), reason: .readerAsked, plan: .nothing),
        Case(
            testDescription: "a new file never needs rewriting, even with no room",
            usage: usage(.incremental, liveMB: 10, freeMB: 50), reason: .readerAsked, volumeFreeMB: 0,
            plan: .release(pages: 50 * megabyte / page)),
        Case(
            testDescription: "when the reader asks, an old file is rewritten while its mail is under 256 MB",
            usage: usage(.off, liveMB: 255, freeMB: 200), reason: .readerAsked, plan: .convert),
        Case(
            testDescription: "an old file with more mail than a rewrite takes on is left as it is",
            usage: usage(.off, liveMB: 256, freeMB: 200), reason: .readerAsked, plan: .nothing),
        Case(
            testDescription: "after a trim, a small old file is rewritten",
            usage: usage(.off, liveMB: 63, freeMB: 200), reason: .afterTrim, plan: .convert),
        Case(
            testDescription: "after a trim, a large old file waits for the reader to ask",
            usage: usage(.off, liveMB: 64, freeMB: 200), reason: .afterTrim, plan: .nothing),
        Case(
            testDescription: "an old file is rewritten only when it may be",
            usage: usage(.off, liveMB: 10, freeMB: 200), reason: .readerAsked, mayConvert: false, plan: .nothing),
        Case(
            testDescription: "an old file is rewritten with twice its size free",
            usage: usage(.off, liveMB: 50, freeMB: 50), reason: .readerAsked, volumeFreeMB: 200, plan: .convert),
        Case(
            testDescription: "an old file isn't rewritten with less than twice its size free",
            usage: usage(.off, liveMB: 50, freeMB: 50), reason: .readerAsked, volumeFreeMB: 199, plan: .nothing),
        Case(
            testDescription: "pages given back while another process read leave the file's tail to empty the log for",
            usage: usage(.incremental, liveMB: 100, freeMB: 0, tailMB: 30), reason: .afterTrim, plan: .emptyLog),
        Case(
            testDescription: "after a trim, a small tail waits",
            usage: usage(.incremental, liveMB: 100, freeMB: 0, tailMB: 3), reason: .afterTrim, plan: .nothing),
        Case(
            testDescription: "when the reader asks, any tail goes",
            usage: usage(.incremental, liveMB: 100, freeMB: 0, tailMB: 1), reason: .readerAsked, plan: .emptyLog),
        Case(
            testDescription: "a log grown past its limit is emptied",
            usage: usage(.incremental, liveMB: 100, freeMB: 0, walMB: 20), reason: .afterTrim, plan: .emptyLog),
        Case(
            testDescription: "a log within its limit is left",
            usage: usage(.incremental, liveMB: 100, freeMB: 0, walMB: 8), reason: .readerAsked, plan: .nothing),
        Case(
            testDescription: "an old file that may not be rewritten still empties its log",
            usage: usage(.off, liveMB: 10, freeMB: 200, walMB: 30), reason: .readerAsked, mayConvert: false,
            plan: .emptyLog),
        Case(
            testDescription: "a rewrite needs room for the log as well as the file",
            usage: usage(.off, liveMB: 50, freeMB: 40, walMB: 10), reason: .readerAsked, volumeFreeMB: 199,
            plan: .emptyLog),
        Case(
            testDescription: "a file that gives pages back on every commit needs nothing",
            usage: usage(.full, liveMB: 50, freeMB: 50), reason: .readerAsked, plan: .nothing),
    ]

    @Test(arguments: cases) func plans(_ example: Case) {
        let plan = DiskReclaim.plan(
            for: example.usage, asked: example.reason, volumeFree: example.volumeFreeMB * Self.megabyte,
            mayConvert: example.mayConvert)
        #expect(plan == example.plan)
    }

    /// The log is cut to nothing only past the size it keeps, so the extensions seldom open an empty one.
    @Test(arguments: [
        (DiskReclaim.journalSizeLimit + 1, DiskReclaim.Checkpoint.truncate),
        (DiskReclaim.journalSizeLimit, .restart),
        (0, .restart),
    ])
    func emptiesTheLog(walBytes: Int64, with checkpoint: DiskReclaim.Checkpoint) {
        #expect(DiskReclaim.Checkpoint(walBytes: walBytes) == checkpoint)
    }
}
