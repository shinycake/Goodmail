/// Tells a read of one resource whether a write stored since overtook it, so a slow read never replaces the write.
/// Reads don't overtake each other.
struct OvertakingWrites {
    /// A read under way, as of the writes stored when it began.
    struct Ticket {
        fileprivate let writes: Int
    }

    private var writes = 0

    /// Begins a read.
    func read() -> Ticket {
        Ticket(writes: writes)
    }

    /// Notes a write, which overtakes every read under way.
    mutating func wrote() {
        writes += 1
    }

    /// Whether no write came since the read began.
    func isCurrent(_ ticket: Ticket) -> Bool {
        ticket.writes == writes
    }
}

/// Tells a read of one resource whether a newer read began since, so an older read never replaces what a newer one
/// stored.
struct LatestRead {
    /// A read under way, by when it began among the others.
    struct Ticket {
        fileprivate let number: Int
    }

    private var begun = 0

    /// Begins a read, which overtakes every read begun before it.
    mutating func begin() -> Ticket {
        begun += 1
        return Ticket(number: begun)
    }

    /// Whether no read began after this one.
    func isLatest(_ ticket: Ticket) -> Bool {
        ticket.number == begun
    }
}
