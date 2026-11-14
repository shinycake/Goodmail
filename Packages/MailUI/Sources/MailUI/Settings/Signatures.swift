import MailCore
import Observation

/// Each account's signature as its editor shows it, and saving edits: to the service when it keeps the signature,
/// else on the device. An account whose signature hasn't been read yet has no entry.
@Observable
public final class Signatures {
    /// One account's signature in the editor.
    enum Entry: Equatable {
        /// The editor shows what is stored.
        case saved(String)
        /// An edit not stored yet: saving, or refused, in which case leaving the editor again retries it.
        case edited(String, stored: String)

        var text: String {
            switch self {
            case .saved(let text), .edited(let text, _): text
            }
        }

        var stored: String {
            switch self {
            case .saved(let stored), .edited(_, let stored): stored
            }
        }
    }

    private(set) var entries: [AccountID: Entry] = [:]
    /// Told when reading or saving a signature fails.
    @ObservationIgnored var failed: (any Error) -> Void = { _ in }

    @ObservationIgnored private let read: (AccountID) async throws -> String?
    @ObservationIgnored private let store: (String, AccountID) async throws -> Void
    /// Saves edits in the order they were made.
    @ObservationIgnored private let saves = TaskChain()

    /// `read` loads the account's stored signature; `store` makes it the signature, at the service first when it
    /// keeps one, and throws if it was refused.
    public init(
        read: @escaping (AccountID) async throws -> String?,
        store: @escaping (String, AccountID) async throws -> Void
    ) {
        self.read = read
        self.store = store
    }

    /// Reads the account's signature once; an edit not stored yet stays as it is.
    func load(_ account: AccountID) async {
        guard entries[account] == nil else { return }
        do {
            let stored = try await read(account) ?? ""
            if entries[account] == nil { entries[account] = .saved(stored) }
        } catch {
            failed(error)
        }
    }

    /// Shows `text` as the account's signature and stores it, after any save before it, unless it is what is
    /// stored: an untouched Gmail signature isn't written back as plain text over its formatting. Trailing blank
    /// lines and spaces are dropped.
    func save(_ text: String, for account: AccountID) {
        guard let entry = entries[account] else { return }
        let text = String(text.reversed().drop(while: \.isWhitespace).reversed())
        entries[account] = text == entry.stored ? .saved(text) : .edited(text, stored: entry.stored)
        saves.run { [self] in
            // Taken when its turn comes, so a later edit is what's stored.
            guard case .edited(let text, _) = entries[account] else { return }
            do {
                try await store(text, account)
                if entries[account]?.text == text { entries[account] = .saved(text) }
            } catch {
                failed(error)
            }
        }
    }

    /// Waits until the edits made so far are stored or refused.
    func settled() async {
        await saves.settled()
    }
}
