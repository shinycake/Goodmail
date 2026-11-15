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

    /// The server removes the folder's messages with it.
    public func deleteLabel(_ id: String) async throws {
        try await session.run { connection in
            guard try await Self.userFolder(id, on: connection) else { return }
            try await refusalsRejected { try await connection.delete(id) }
        }
    }

    /// Whether `wireName` is one of the user's folders, which are the only ones the app renames or deletes.
    private static func userFolder(_ wireName: String, on connection: IMAPConnection) async throws -> Bool {
        Folders(try await connection.mailboxes()).all.contains { $0.wireName == wireName && $0.role == nil }
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
