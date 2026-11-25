import MailCore
import Testing

struct MinimizedDraftWindowsTests {
    /// What a drop held for a window stands in as, a name; a read, a number.
    private typealias Windows = MinimizedDraftWindows<String, Int>

    /// What a finished read of one window's message delivered: `nil` when it was stale.
    private func delivered(_ read: Windows.Read) -> String?? {
        switch read {
        case .delivered(let holding): holding.values.first
        case .stale: nil
        }
    }

    /// Everything a finished read delivered, by name: `nil` when it was stale.
    private func handed(_ read: Windows.Read) -> [String: String]? {
        guard case .delivered(let holding) = read else { return nil }
        return holding
    }

    /// A window under `name` that went away before reading back its message, for which `held` was dropped.
    private func away(_ name: String, holding held: String, in windows: inout Windows) -> DraftWindowTicket {
        _ = windows.reserve(DraftWindowTicket(window: name), holding: held)
        let window = DraftWindowTicket(window: name)
        _ = windows.take(window) { 1 }
        windows.close(window)
        return window
    }

    private func spared(claiming ticket: DraftWindowTicket, in windows: inout Windows) -> Set<String> {
        var spared: Set<String> = []
        _ = windows.claim(ticket) { sparing in
            spared = sparing
            return 0
        }
        return spared
    }

    @Test func `a claim spares the windows open, reserved or reading`() {
        var windows = Windows()
        _ = windows.reserve(DraftWindowTicket(window: "moving"), holding: nil)
        let first = DraftWindowTicket(window: "first")
        _ = windows.claim(first) { _ in 1 }
        _ = windows.finishedReading(first)
        _ = windows.take(DraftWindowTicket(window: "restored")) { 2 }
        #expect(spared(claiming: DraftWindowTicket(window: "new"), in: &windows) == ["moving", "first", "restored"])
    }

    @Test func `a closed window's messages are claimed again`() {
        var windows = Windows()
        let first = DraftWindowTicket(window: "first")
        _ = windows.claim(first) { _ in 1 }
        windows.close(first)
        #expect(spared(claiming: DraftWindowTicket(window: "second"), in: &windows).isEmpty)
    }

    @Test func `what was held for a reserved window comes with its read, once`() {
        var windows = Windows()
        _ = windows.reserve(DraftWindowTicket(window: "moving"), holding: "photo")
        let window = DraftWindowTicket(window: "moving")
        _ = windows.take(window) { 1 }
        let first = windows.finishedReading(window)
        let second = windows.finishedReading(window)
        #expect(delivered(first) == .some("photo"))
        #expect(delivered(second) == nil, "stale once read")
    }

    @Test func `a window that won't open lets go of what was held for it`() {
        var windows = Windows()
        let reservation = DraftWindowTicket(window: "moving")
        _ = windows.reserve(reservation, holding: "photo")
        let ended = windows.close(reservation)
        let window = DraftWindowTicket(window: "moving")
        _ = windows.take(window) { 1 }
        let read = windows.finishedReading(window)
        #expect(ended == nil, "no read to end")
        #expect(delivered(read) == .some(nil))
    }

    @Test func `a window closed while reading ends its read, which delivers nothing`() {
        var windows = Windows()
        let window = DraftWindowTicket(window: "first")
        _ = windows.claim(window) { _ in 7 }
        let ended = windows.close(window)
        let read = windows.finishedReading(window)
        #expect(ended == 7)
        #expect(delivered(read) == nil)
    }

    /// Undo Send reopens a message in a window of the same name while the old one is still closing.
    @Test func `an old window of the same name leaves the new one's reservation alone`() {
        var windows = Windows()
        let old = DraftWindowTicket(window: "compose")
        _ = windows.take(old) { 1 }
        let replaced = windows.reserve(DraftWindowTicket(window: "compose"), holding: "photo")
        let oldFinished = windows.finishedReading(old)
        let oldOwns = windows.owns(old)
        let oldClosed = windows.close(old)
        let new = DraftWindowTicket(window: "compose")
        _ = windows.take(new) { 2 }
        let newRead = windows.finishedReading(new)
        #expect(replaced == 1, "the old read is ended")
        #expect(delivered(oldFinished) == nil)
        #expect(!oldOwns, "the old window writes nothing under the name now")
        #expect(oldClosed == nil)
        #expect(delivered(newRead) == .some("photo"))
    }

    @Test func `a new read in a window's name hands back the read it replaces`() {
        var windows = Windows()
        let first = DraftWindowTicket(window: "compose")
        _ = windows.take(first) { 1 }
        let replaced = windows.take(DraftWindowTicket(window: "compose")) { 2 }
        #expect(replaced == 1)
    }

    /// The system can put a message window away before it has read its message back, and bring it back later.
    @Test func `a drop waits for its window to come back`() {
        var windows = Windows()
        _ = away("compose", holding: "photo", in: &windows)
        let back = DraftWindowTicket(window: "compose")
        _ = windows.take(back) { 2 }
        let read = windows.finishedReading(back)
        #expect(delivered(read) == .some("photo"))
    }

    @Test func `a mail window that claims an away window's message takes its drop`() {
        var windows = Windows()
        _ = away("compose", holding: "photo", in: &windows)
        let mail = DraftWindowTicket(window: "mail")
        var spared: Set<String> = ["unset"]
        _ = windows.claim(mail) { sparing in
            spared = sparing
            return 2
        }
        let read = windows.finishedReading(mail)
        let back = DraftWindowTicket(window: "compose")
        _ = windows.take(back) { 3 }
        let backRead = windows.finishedReading(back)
        #expect(spared.isEmpty, "its message is free")
        #expect(handed(read) == ["compose": "photo"])
        #expect(delivered(backRead) == .some(nil), "handed over once")
    }

    @Test func `a claim ended by its window closing leaves the drop for the next`() {
        var windows = Windows()
        _ = away("compose", holding: "photo", in: &windows)
        let mail = DraftWindowTicket(window: "mail")
        _ = windows.claim(mail) { _ in 2 }
        let ended = windows.close(mail)
        let next = DraftWindowTicket(window: "next")
        _ = windows.claim(next) { _ in 3 }
        let read = windows.finishedReading(next)
        #expect(ended == 2)
        #expect(handed(read) == ["compose": "photo"])
    }

    @Test func `a discarded window's drop is let go`() {
        var windows = Windows()
        let gone = away("compose", holding: "photo", in: &windows)
        windows.discard(gone)
        let again = DraftWindowTicket(window: "compose")
        _ = windows.take(again) { 2 }
        let read = windows.finishedReading(again)
        #expect(delivered(read) == .some(nil))
    }

    @Test func `discarding an old window leaves the drop waiting for a newer one of its name`() {
        var windows = Windows()
        let old = away("compose", holding: "first", in: &windows)
        _ = away("compose", holding: "second", in: &windows)
        windows.discard(old)
        let back = DraftWindowTicket(window: "compose")
        _ = windows.take(back) { 3 }
        let read = windows.finishedReading(back)
        #expect(delivered(read) == .some("second"))
    }

    @Test func `discarding a window leaves one open under its name`() {
        var windows = Windows()
        let window = DraftWindowTicket(window: "compose")
        _ = windows.reserve(window, holding: "photo")
        windows.discard(window)
        #expect(windows.owns(window))
        #expect(spared(claiming: DraftWindowTicket(window: "mail"), in: &windows) == ["compose"])
    }
}
