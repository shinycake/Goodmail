public import Foundation

/// One window's hold on its name among the minimized messages. Two windows can share a name, as a message window Undo
/// Send reopens while the old one is still closing, so each holds a ticket of its own, and only the window holding the
/// ticket a name is under now changes it.
public struct DraftWindowTicket: Hashable, Sendable {
    /// The name the window's messages are kept under.
    public let window: String
    /// Tells this window from another of the same name, and lets the system's record of the window name it again.
    public let id: UUID

    public init(window: String, id: UUID = UUID()) {
        self.window = window
        self.id = id
    }
}

/// The app's windows as their minimized messages see them, each in one state from the moment it is asked for, or
/// opens, until it closes. An open window's messages are its own; the messages of a window no longer here are free for
/// the next window that claims them. `Held` is what was dropped on a mail window for a message moving into a window of
/// its own, held until a window has read that message back; `Reading` is a window's read of its messages under way.
public struct MinimizedDraftWindows<Held, Reading> {
    /// What was dropped for the message under a name, and the window it waits for.
    private struct Kept {
        var from: DraftWindowTicket
        var held: Held
    }

    private enum Window {
        /// Asked of the system and not connected yet, so no other window claims the message kept for it meanwhile.
        case reserved(DraftWindowTicket, holding: Held?)
        /// Reading messages back, with what was dropped for them, by name, until the read delivers it.
        case reading(DraftWindowTicket, Reading, holding: [String: Kept])
        /// Its messages are read back.
        case open(DraftWindowTicket)
        /// Closed before a read delivered what was dropped for its message, as the system put the window away. Its
        /// message is free; what was dropped waits for the window to come back, for the window that claims the message,
        /// or until the window is discarded.
        case away(Kept)

        /// The window holding the name, while one does.
        var owner: DraftWindowTicket? {
            switch self {
            case .reserved(let ticket, _), .reading(let ticket, _, _), .open(let ticket): ticket
            case .away: nil
            }
        }

        var read: Reading? {
            guard case .reading(_, let read, _) = self else { return nil }
            return read
        }
    }

    /// What a read that ended brings.
    public enum Read {
        /// The window still waits for it, with what was dropped for the messages it read, by their names.
        case delivered(holding: [String: Held])
        /// The window closed, or another window took its name, since the read began: nothing waits for it.
        case stale
    }

    private var windows: [String: Window] = [:]

    public init() {}

    /// Holds `ticket`'s window open before it has connected, with `held` for its composer. Returns the read of a window
    /// of the same name it replaces, to end.
    public mutating func reserve(_ ticket: DraftWindowTicket, holding held: Held?) -> Reading? {
        let replaced = windows[ticket.window]?.read
        windows[ticket.window] = .reserved(ticket, holding: held)
        return replaced
    }

    /// `ticket`'s window reads back the messages of the windows no longer open, with what was dropped for any of them
    /// whose window went away before reading it back. `read` starts that read, sparing the messages of the windows
    /// open now. Returns the read of a window of the same name it replaces, to end.
    public mutating func claim(
        _ ticket: DraftWindowTicket, reading read: (_ sparing: Set<String>) -> Reading
    ) -> Reading? {
        var sparing: Set<String> = []
        var handed: [String: Kept] = [:]
        for (name, window) in windows where name != ticket.window {
            switch window {
            case .away(let kept): handed[name] = kept
            case .reserved, .reading, .open: sparing.insert(name)
            }
        }
        for name in handed.keys { windows[name] = nil }
        let replaced = windows[ticket.window]?.read
        windows[ticket.window] = .reading(ticket, read(sparing), holding: handed)
        return replaced
    }

    /// `ticket`'s window reads back the messages kept for it alone, with what was dropped for them when it was
    /// reserved or before it went away, which the read delivers (`finishedReading(_:)`). `read` starts that read.
    /// Returns the read of a window of the same name it replaces, to end.
    public mutating func take(_ ticket: DraftWindowTicket, reading read: () -> Reading) -> Reading? {
        let before = windows[ticket.window]
        let held: Held? =
            switch before {
            case .reserved(_, let held): held
            case .reading(_, _, let holding): holding[ticket.window]?.held
            case .away(let kept): kept.held
            case .open, nil: nil
            }
        let holding = held.map { [ticket.window: Kept(from: ticket, held: $0)] } ?? [:]
        windows[ticket.window] = .reading(ticket, read(), holding: holding)
        return before?.read
    }

    /// The read `ticket`'s window started is done: what it brings, which only a window still waiting for it gets.
    public mutating func finishedReading(_ ticket: DraftWindowTicket) -> Read {
        guard case .reading(let reading, _, let holding) = windows[ticket.window], reading == ticket else {
            return .stale
        }
        windows[ticket.window] = .open(ticket)
        return .delivered(holding: holding.mapValues(\.held))
    }

    /// Whether `ticket`'s window may write the messages under its name: no other window holds that name now.
    public func owns(_ ticket: DraftWindowTicket) -> Bool {
        windows[ticket.window]?.owner.map { $0 == ticket } ?? true
    }

    /// `ticket`'s window closed, or won't open: its messages are free for the next window, and what was held for it
    /// goes, unless its read hadn't delivered it yet, when it waits again, as before the read. Nothing changes once
    /// another window took the name. Returns its read still under way, to end.
    @discardableResult
    public mutating func close(_ ticket: DraftWindowTicket) -> Reading? {
        guard let window = windows[ticket.window], window.owner == ticket else { return nil }
        windows[ticket.window] = nil
        if case .reading(_, _, let holding) = window {
            for (name, kept) in holding where windows[name] == nil { windows[name] = .away(kept) }
        }
        return window.read
    }

    /// `ticket`'s window is gone for good, as the system discarded its session: what waited for it goes. What waits
    /// for another window of the same name stays.
    public mutating func discard(_ ticket: DraftWindowTicket) {
        guard case .away(let kept) = windows[ticket.window], kept.from == ticket else { return }
        windows[ticket.window] = nil
    }
}
