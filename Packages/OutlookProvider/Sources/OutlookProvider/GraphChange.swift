import Foundation
import MailCore

/// One request that brings a message in line with a thread action. Outlook keeps Unread and Starred as properties
/// and files each message in exactly one folder, so a Gmail-style label change becomes at most one of each per
/// message.
enum GraphChange: Equatable, Sendable {
    case markRead(Bool)
    case flag(Bool)
    case move(toFolder: String)

    enum Failure: Error, Equatable {
        /// The action names a label no folder holds, such as a folder deleted since, or archives in a mailbox
        /// without Archive.
        case noFolder
        /// The action files the thread in two folders at once, which Outlook can't do.
        case severalFolders
    }

    /// The changes that give `message` the labels `action` leaves it with, read before move. Empty when it already
    /// has them, so replaying an action changes nothing.
    ///
    /// A message lands in the folder of the label the action adds. Sent mail and drafts stay put, as Gmail keeps
    /// their labels, unless the thread goes to Trash or Spam whole. A message that loses its folder's label and gains
    /// none goes to Archive, as a Gmail message out of the Inbox is archived.
    static func changes(
        for action: ThreadAction, to message: GraphMessage, in folders: FolderDirectory
    ) throws -> [GraphChange] {
        let (add, remove) = action.labelChange
        var changes: [GraphChange] = []
        if let unread = Self.state(of: SystemLabel.unread, adding: add, removing: remove),
            unread != (message.isRead == false)
        {
            changes.append(.markRead(!unread))
        }
        if let starred = Self.state(of: SystemLabel.starred, adding: add, removing: remove),
            starred != message.isFlagged
        {
            changes.append(.flag(starred))
        }
        let current = message.parentFolderId.flatMap(folders.label(forFolder:))
        if let destination = try folder(adding: add, removing: remove, from: current, in: folders),
            destination != message.parentFolderId
        {
            changes.append(.move(toFolder: destination))
        }
        return changes
    }

    /// Whether the action leaves a flag label on (`true`) or off (`false`), or `nil` when it doesn't touch it.
    /// Adding wins over removing, as in `ThreadAction.applied(to:)`.
    private static func state(of flag: String, adding add: Set<String>, removing remove: Set<String>) -> Bool? {
        if add.contains(flag) { return true }
        if remove.contains(flag) { return false }
        return nil
    }

    /// The folder the message belongs in after the action, or `nil` where it is.
    private static func folder(
        adding add: Set<String>, removing remove: Set<String>, from current: String?, in folders: FolderDirectory
    ) throws -> String? {
        let added = add.subtracting([SystemLabel.unread, SystemLabel.starred])
        guard added.count <= 1 else { throw Failure.severalFolders }
        if let label = added.first {
            let wholeThread: Set<String> = [SystemLabel.trash, SystemLabel.spam]
            let staysPut: Set<String> = [SystemLabel.sent, SystemLabel.draft]
            if let current, staysPut.contains(current), !wholeThread.contains(label) { return nil }
            guard let folder = folders.folderID(forLabel: label) else { throw Failure.noFolder }
            return folder
        }
        guard let current, remove.contains(current) else { return nil }
        guard let archive = folders.wellKnown[.archive] else { throw Failure.noFolder }
        return archive
    }
}

extension ThreadAction {
    /// The labels the action adds and removes. Trash and untrash are label changes too, as `applied(to:)` reads them.
    fileprivate var labelChange: (add: Set<String>, remove: Set<String>) {
        switch self {
        case .modifyLabels(let add, let remove): (add, remove)
        case .trash: ([SystemLabel.trash], [SystemLabel.inbox])
        case .untrash: ([], [SystemLabel.trash])
        }
    }
}

extension GraphMessage {
    /// What `perform` reads to plan a message's changes.
    static let stateFields = "id,isRead,flag,parentFolderId"

    var isFlagged: Bool { flag?.flagStatus == "flagged" }
}

extension GraphTransport {
    /// Sends one change. A message that is gone is not an error: the action has nothing left to change on it. Throws
    /// `ProviderError.rejected` for a change Graph refuses as invalid.
    func apply(_ change: GraphChange, toMessage id: String) async throws {
        let url = Self.baseURL.appending(path: "me/messages/\(id)")
        do {
            switch change {
            case .markRead(let read):
                try await send(url, method: "PATCH", json: ReadPatch(isRead: read))
            case .flag(let flagged):
                try await send(url, method: "PATCH", json: FlagPatch(flag: .init(flagged: flagged)))
            case .move(let folder):
                try await send(url.appending(path: "move"), method: "POST", json: MoveRequest(destinationId: folder))
            }
        } catch let error as GraphError where error.status == 404 {
            return
        } catch let error as GraphError where error.status == 400 {
            throw ProviderError.rejected
        }
    }

    private func send(_ url: URL, method: String, json body: some Encodable) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        try await send(url, method: method, payload: (try encoder.encode(body), "application/json"))
    }
}

private struct ReadPatch: Encodable {
    let isRead: Bool
}

private struct FlagPatch: Encodable {
    struct Flag: Encodable {
        let flagStatus: String

        init(flagged: Bool) {
            flagStatus = flagged ? "flagged" : "notFlagged"
        }
    }

    let flag: Flag
}

private struct MoveRequest: Encodable {
    let destinationId: String
}
