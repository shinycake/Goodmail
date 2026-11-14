import Foundation
import MailCore

/// One request that brings a message in line with a thread action. Outlook keeps Unread and Starred as properties
/// and files each message in exactly one folder, so a Gmail-style label change becomes at most one of each per
/// message.
enum GraphChange: Equatable, Sendable {
    case markRead(Bool)
    case flag(Bool)
    case move(toFolder: String)
    /// Deletes the message for good, past Recoverable Items.
    case permanentDelete

    enum Failure: Error, Equatable {
        /// The action names a label no folder holds, such as a folder deleted since, or archives in a mailbox
        /// without Archive.
        case noFolder
        /// The action files the thread in two folders at once, which Outlook can't do.
        case severalFolders
    }

    /// The changes that give `message` the labels `action` leaves it with, read before move, or that delete it for
    /// good when the action deletes it. Empty when it already has them, so replaying an action changes nothing.
    ///
    /// A message lands in the folder of the label the action adds. Sent mail and drafts stay put, as Gmail keeps
    /// their labels, unless the thread goes to Trash or Spam whole. A message that loses its folder's label and gains
    /// none goes to Archive, as a Gmail message out of the Inbox is archived.
    static func changes(
        for action: ThreadAction, to message: GraphMessage, in folders: FolderDirectory
    ) throws -> [GraphChange] {
        let current = message.parentFolderId.flatMap(folders.label(forFolder:))
        switch action {
        case .modifyLabels(let add, let remove):
            return try changes(adding: add, removing: remove, to: message, in: current, of: folders)
        case .trash:
            return try changes(
                adding: [SystemLabel.trash], removing: [SystemLabel.inbox], to: message, in: current, of: folders)
        case .untrash:
            return try changes(adding: [], removing: [SystemLabel.trash], to: message, in: current, of: folders)
        case .deleteForever:
            return current == SystemLabel.trash ? [.permanentDelete] : []
        }
    }

    /// The changes for a label change, as `ThreadAction.outcome(for:)` reads Trash and untrash too.
    private static func changes(
        adding add: Set<String>, removing remove: Set<String>, to message: GraphMessage, in current: String?,
        of folders: FolderDirectory
    ) throws -> [GraphChange] {
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
        if let destination = try folder(adding: add, removing: remove, from: current, in: folders),
            destination != message.parentFolderId
        {
            changes.append(.move(toFolder: destination))
        }
        return changes
    }

    /// Whether the action leaves a flag label on (`true`) or off (`false`), or `nil` when it doesn't touch it.
    /// Adding wins over removing, as in `ThreadAction.outcome(for:)`.
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

/// The changes one message of a conversation needs, empty when it already matches the action.
struct MessagePlan: Sendable {
    let messageID: String
    let changes: [GraphChange]
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
            case .permanentDelete:
                try await send(url.appending(path: "permanentDelete"), method: "POST", payload: nil)
            }
        } catch let error as GraphError where error.status == 404 {
            return
        } catch let error as GraphError where error.status == 400 {
            throw ProviderError.rejected
        }
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
