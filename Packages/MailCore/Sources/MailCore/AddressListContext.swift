/// Where a scan of an address list stands, one character at a time. A quote opens and closes anywhere, even inside
/// angle brackets as in `<"a,b"@example.com>`; angle brackets inside quotes are only text.
enum AddressListContext: Equatable {
    case plain
    case quoted
    case angled
    case quotedInAngles

    /// The context after `character`, the one transition this scan has.
    func after(_ character: Character) -> AddressListContext {
        switch (self, character) {
        case (.plain, "\""): .quoted
        case (.quoted, "\""): .plain
        case (.angled, "\""): .quotedInAngles
        case (.quotedInAngles, "\""): .angled
        case (.plain, "<"): .angled
        case (.angled, ">"): .plain
        default: self
        }
    }
}
