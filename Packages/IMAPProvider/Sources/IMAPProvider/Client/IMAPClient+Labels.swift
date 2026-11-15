import Foundation
import MailCore

/// The user's folders, which stand in for labels. A user folder's label is its name on the wire, in modified UTF-7,
/// so a renamed folder is a new label; the folder list then differs from the cursor's, and the next sync resyncs.
extension IMAPClient {
    public func createLabel(named name: String) async throws -> MailLabel {
        let wireName = try Self.wireName(name)
        try await refusalsRejected { try await session.run { connection in try await connection.create(wireName) } }
        return MailLabel(id: wireName, name: name, kind: .user)
    }

    /// The server renames the folders under it too (RFC 3501 §6.3.5).
    public func renameLabel(_ id: String, to name: String) async throws {
        let wireName = try Self.wireName(name)
        try await session.run { connection in
            guard try await Self.userFolder(id, on: connection) else { throw ProviderError.notFound }
            try await refusalsRejected { try await connection.rename(id, to: wireName) }
        }
    }

    /// The server removes each folder's messages with it. A deleted folder's inferiors stay (RFC 3501 §6.3.4), so
    /// the folders under it go first; a folder with a role among them stays.
    public func deleteLabel(_ id: String) async throws {
        try await session.run { connection in
            let mailboxes = try await connection.mailboxes()
            guard Self.isUserFolder(id, in: mailboxes) else { return }
            let nested = Self.nested(in: id, among: mailboxes)
            try await refusalsRejected {
                for wireName in nested + [id] { try await connection.delete(wireName) }
            }
        }
    }

    /// The folders under `wireName` but those with a role, each before the one that holds it. A server without a
    /// hierarchy has none.
    static func nested(in wireName: String, among mailboxes: [IMAPMailbox]) -> [String] {
        guard let delimiter = mailboxes.first(where: { $0.wireName == wireName })?.delimiter else { return [] }
        let roles = Set(Folders(mailboxes).all.filter { $0.role != nil }.map(\.wireName))
        return mailboxes.map(\.wireName)
            .filter { $0.hasPrefix(wireName + delimiter) && !roles.contains($0) }
            // Backwards by name, each folder comes before the one that holds it.
            .sorted(by: >)
    }

    /// Whether `wireName` is one of the user's folders, which are the only ones the app renames or deletes.
    private static func userFolder(_ wireName: String, on connection: IMAPConnection) async throws -> Bool {
        isUserFolder(wireName, in: try await connection.mailboxes())
    }

    private static func isUserFolder(_ wireName: String, in mailboxes: [IMAPMailbox]) -> Bool {
        Folders(mailboxes).all.contains { $0.wireName == wireName && $0.role == nil }
    }

    /// A folder name the server refuses, as one already taken, is rejected.
    private func refusalsRejected(_ body: () async throws -> Void) async throws {
        do {
            try await body()
        } catch IMAPError.refused, IMAPError.invalid {
            throw ProviderError.rejected
        }
    }

    /// The name on the wire. A blank name, or one with a line break, can't be a folder.
    static func wireName(_ name: String) throws -> String {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty, !name.contains(where: \.isNewline) else {
            throw ProviderError.rejected
        }
        return ModifiedUTF7.encode(name)
    }
}
