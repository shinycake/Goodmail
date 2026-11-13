import Foundation
import MailCore

/// The folders every Outlook mailbox has, by Graph's well-known names. Outlook files each message in one folder;
/// the domain model reads the system ones as Gmail's system labels.
enum WellKnownFolder: String, CaseIterable, Sendable {
    case inbox, sentitems, drafts, deleteditems, junkemail, archive, outbox, conversationhistory

    /// The system label a message filed here carries. Archive has none, as archived Gmail mail is simply out of the
    /// Inbox; Outbox and Conversation History aren't shown.
    var label: String? {
        switch self {
        case .inbox: SystemLabel.inbox
        case .sentitems: SystemLabel.sent
        case .drafts: SystemLabel.draft
        case .deleteditems: SystemLabel.trash
        case .junkemail: SystemLabel.spam
        case .archive, .outbox, .conversationhistory: nil
        }
    }
}

/// A mailbox's folders: which ID is which well-known folder, and the user's own, which stand in for user labels.
struct FolderDirectory: Equatable, Sendable {
    /// Folder IDs by well-known name. A mailbox may lack one, such as Archive on an older account.
    var wellKnown: [WellKnownFolder: String]
    /// The user's folders, named by their path, as in `Projects/Goodmail`.
    var user: [MailLabel]

    /// The label a message filed in `folderID` carries: a system label, the user folder's ID, or none.
    func label(forFolder folderID: String) -> String? {
        if let folder = wellKnown.first(where: { $0.value == folderID })?.key { return folder.label }
        return user.contains { $0.id == folderID } ? folderID : nil
    }

    /// The folder that holds the messages carrying `label`, when one does. Unread and Starred are flags, not folders.
    func folderID(forLabel label: String) -> String? {
        if let folder = WellKnownFolder.allCases.first(where: { $0.label == label }) { return wellKnown[folder] }
        return user.contains { $0.id == label } ? label : nil
    }

    /// The system labels this mailbox has, then the user's folders.
    var labels: [MailLabel] {
        let system = WellKnownFolder.allCases.compactMap { folder -> MailLabel? in
            guard let label = folder.label, wellKnown[folder] != nil else { return nil }
            return MailLabel(id: label, name: label, kind: .system)
        }
        let flags = [SystemLabel.unread, SystemLabel.starred].map { MailLabel(id: $0, name: $0, kind: .system) }
        return system + flags + user
    }
}

/// Loads the folder directory once per client and keeps it; folders change rarely, and a sync reloads it.
actor FolderCache {
    private var directory: FolderDirectory?

    func directory(loading load: @Sendable () async throws -> FolderDirectory) async throws -> FolderDirectory {
        if let directory { return directory }
        let loaded = try await load()
        directory = loaded
        return loaded
    }

    func store(_ directory: FolderDirectory) {
        self.directory = directory
    }
}

extension GraphTransport {
    /// Every folder: the well-known ones by name, then the rest of the tree as the user's folders.
    func folderDirectory() async throws -> FolderDirectory {
        var wellKnown: [WellKnownFolder: String] = [:]
        try await withThrowingTaskGroup(of: (WellKnownFolder, String?).self) { group in
            for folder in WellKnownFolder.allCases {
                group.addTask {
                    do {
                        let found: GraphFolder = try await get("me/mailFolders/\(folder.rawValue)")
                        return (folder, found.id)
                    } catch let error as GraphError where error.status == 404 {
                        return (folder, nil)
                    }
                }
            }
            for try await (folder, id) in group { wellKnown[folder] = id }
        }
        let systemIDs = Set(wellKnown.values)
        var user: [MailLabel] = []
        try await collectFolders(under: nil, path: [], skipping: systemIDs, into: &user)
        return FolderDirectory(wellKnown: wellKnown, user: user)
    }

    /// Walks the folder tree from the root, or from `parent`, depth first.
    private func collectFolders(
        under parent: String?, path: [String], skipping systemIDs: Set<String>, into labels: inout [MailLabel]
    ) async throws {
        let base = parent.map { "me/mailFolders/\($0)/childFolders" } ?? "me/mailFolders"
        var next: URL? = Self.baseURL.appending(path: base).appending(queryItems: [
            URLQueryItem(name: "$top", value: "100"),
            URLQueryItem(name: "$select", value: "id,displayName,childFolderCount"),
        ])
        while let url = next {
            let page: GraphPage<GraphFolder> = try await get(url)
            for folder in page.value {
                let folderPath = path + [folder.displayName]
                // System folders' subfolders are the user's own, as Gmail's nested labels are.
                if !systemIDs.contains(folder.id) {
                    labels.append(MailLabel(id: folder.id, name: folderPath.joined(separator: "/"), kind: .user))
                }
                if (folder.childFolderCount ?? 0) > 0 {
                    try await collectFolders(under: folder.id, path: folderPath, skipping: systemIDs, into: &labels)
                }
            }
            next = page.nextLink
        }
    }
}
