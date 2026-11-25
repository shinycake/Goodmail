import Foundation
import MailCore

/// Keeps the account's Inbox in IDLE (RFC 2177) on a connection of its own, so new mail and changes made elsewhere,
/// such as a message read or deleted on another device, are reported as they happen rather than at the next poll.
///
/// IDLE watches one mailbox, so other folders still wait for the poll. A lost connection is opened again, sooner
/// at first and then less often, up to every five minutes, until the watch is cancelled.
struct IMAPWatcher: Sendable {
    let connector: IMAPConnector
    /// How long one IDLE lasts before it is started again. RFC 2177 allows 29 minutes, but mobile networks forget
    /// a quiet connection sooner, and ending the IDLE is how a connection that died unnoticed is found.
    var renewal: Duration = .seconds(10 * 60)
    /// How long to wait before connecting again after this many failures in a row.
    var retryDelay: @Sendable (Int) -> Duration = Self.backoff

    /// Five seconds after the first failure, doubling each time, up to five minutes.
    static func backoff(_ failures: Int) -> Duration {
        .seconds(min(5 << min(failures - 1, 6), 300))
    }

    /// Calls `changed` each time the server reports a change in the Inbox, and after each time it connects, for what
    /// changed while nothing was watching, until the task is cancelled. Returns when the server can't IDLE, which
    /// leaves the account to polling. Throws `CancellationError` once cancelled, and the errors that connecting
    /// again won't fix: a refused password, or a server that won't encrypt.
    func watch(_ changed: @escaping @Sendable () async -> Void) async throws {
        var failures = 0
        while true {
            do {
                try await watchInbox(changed, failures: &failures)
                return
            } catch _ where Task.isCancelled {
                throw CancellationError()
            } catch IMAPError.authenticationFailed {
                throw IMAPError.authenticationFailed
            } catch IMAPError.insecure {
                throw IMAPError.insecure
            } catch {
                failures += 1
                try await Task.sleep(for: retryDelay(failures))
            }
        }
    }

    /// Watches the Inbox on one connection until it fails. Returns at once when the server can't IDLE. `failures`
    /// is reset once an IDLE ends as it should, as the connection has shown it works.
    private func watchInbox(_ changed: @Sendable () async -> Void, failures: inout Int) async throws {
        let connection = try await connector.open()
        do {
            guard try await connection.supports("IDLE") else {
                try? await connection.logout()
                return
            }
            try await connection.select("INBOX")
            await changed()
            while true {
                let end = try await connection.idle(renewingAfter: renewal)
                failures = 0
                if end == .changed { await changed() }
            }
        } catch {
            await connection.close()
            throw error
        }
    }
}
