public import Foundation

/// What holds a paused game still, and the one way each hold carries on: the reader picks Resume on the pause card,
/// which counts down before anything moves; the reader taps the cross or the new mail and is asked first whether to
/// leave the game. Every change is one of the functions here, so the screen never has to work out which combination it
/// is in.
public enum PlaneGameHold: Equatable, Sendable {
    /// The pause card shows and waits for the reader.
    case card
    /// Asking whether to leave the game. Staying goes back to `staying`.
    case askingToLeave(staying: Staying)
    /// Counting down to carry on, `left` seconds from moving again.
    case countingDown(left: TimeInterval)

    /// Where staying in the game after the question goes back to.
    public enum Staying: Equatable, Sendable {
        /// The pause card it was asked from.
        case card
        /// A countdown from the start, as the game was in play or counting down when it was asked.
        case countdown
    }

    /// How long a countdown lasts, in seconds.
    public static let countdown: TimeInterval = 3

    /// A countdown from the start.
    public static var counting: PlaneGameHold { .countingDown(left: countdown) }

    /// The hold `seconds` later, or `nil` once a countdown has run out and the game moves again. Only a countdown
    /// changes with time: the card and the question wait for the reader.
    public func advanced(by seconds: TimeInterval) -> PlaneGameHold? {
        guard case .countingDown(let left) = self else { return self }
        let remaining = left - max(seconds, 0)
        return remaining > 0 ? .countingDown(left: remaining) : nil
    }

    /// The reader asked to carry on from the pause card: the countdown starts.
    public var resumed: PlaneGameHold {
        if case .card = self { .counting } else { self }
    }

    /// Something paused the game again, as the pause sign or the app going inactive: a countdown stops and the card
    /// shows. A question already asked keeps waiting for its answer.
    public var paused: PlaneGameHold {
        if case .countingDown = self { .card } else { self }
    }

    /// The reader asked to leave: the game asks before it does, and staying goes back to what showed.
    public var askingToLeave: PlaneGameHold {
        switch self {
        case .card: .askingToLeave(staying: .card)
        case .countingDown: .askingToLeave(staying: .countdown)
        case .askingToLeave: self
        }
    }

    /// The reader chose to stay in the game.
    public var stayed: PlaneGameHold {
        switch self {
        case .askingToLeave(staying: .card): .card
        case .askingToLeave(staying: .countdown): .counting
        case .card, .countingDown: self
        }
    }

    /// The number the countdown shows, 3, 2 then 1, or `nil` when it isn't counting down.
    public var count: Int? {
        guard case .countingDown(let left) = self else { return nil }
        return min(max(Int(left.rounded(.up)), 1), Int(Self.countdown))
    }
}
