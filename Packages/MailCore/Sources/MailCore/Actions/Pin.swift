import Foundation

/// The persistence pinning needs. A pin keeps a thread at the top of every list it is in, on this device only: no
/// service has pins. `MailStore` implements it.
public protocol PinStore: Sendable {
    /// The pinned threads among `threads`.
    func pins(among threads: [ThreadSummary.ID]) throws -> Set<ThreadSummary.ID>
    /// Pins each thread mapped to `true` and unpins each one mapped to `false`.
    func setPins(_ pins: [ThreadSummary.ID: Bool]) throws
}
