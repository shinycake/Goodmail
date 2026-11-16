import Foundation
public import MailCore

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLSession on Linux
#endif

/// The user's folders, which stand in for labels. A label's name is its folder's path, as `Inbox/Receipts`, so
/// creating one makes the folders on its path that don't exist yet, and renaming one to another path moves it there.
extension OutlookClient {
    public func createLabel(named name: String) async throws -> MailLabel {
        let path = try Self.components(of: name)
        let parent = try await folderID(at: path.dropLast(), creating: true)
        let folder = try await createFolder(named: path[path.count - 1], in: parent)
        return MailLabel(id: folder.id, name: path.joined(separator: "/"), kind: .user)
    }

    public func renameLabel(_ id: String, to name: String) async throws {
        let directory = try await graph.folderDirectory()
        await folders.store(directory)
        guard let old = directory.user.first(where: { $0.id == id }) else { throw ProviderError.notFound }
        let from = try Self.components(of: old.name)
        let to = try Self.components(of: name)
        try await translatingFailures {
            if from.last != to.last {
                try await graph.send(
                    Self.folderURL(id), method: "PATCH", json: FolderBody(displayName: to[to.count - 1]))
            }
            if from.dropLast() != to.dropLast() {
                let parent = try await folderID(at: to.dropLast(), creating: true)
                try await graph.send(
                    Self.folderURL(id).appending(path: "move"), method: "POST",
                    json: FolderMove(destinationId: parent ?? "msgfolderroot"))
            }
        }
    }

    /// Outlook moves the folder, its subfolders and their mail to Deleted Items.
    public func deleteLabel(_ id: String) async throws {
        do {
            try await graph.send(Self.folderURL(id), method: "DELETE", payload: nil)
        } catch let error as GraphError where error.status == 404 {
            return
        }
    }

    /// The folder at `path` from the top of the mailbox, `nil` for the top itself. With `creating`, the folders on
    /// the path that don't exist yet are made; without it, a missing one is `ProviderError.notFound`.
    private func folderID(at path: ArraySlice<String>, creating: Bool) async throws -> String? {
        var parent: String?
        for name in path {
            let base = parent.map { "me/mailFolders/\($0)/childFolders" } ?? "me/mailFolders"
            let found: GraphPage<GraphFolder> = try await graph.get(
                base,
                query: [
                    URLQueryItem(name: "$filter", value: "displayName eq \(Self.literal(name))"),
                    URLQueryItem(name: "$select", value: "id,displayName,childFolderCount"),
                ])
            if let folder = found.value.first {
                parent = folder.id
            } else if creating {
                parent = try await createFolder(named: name, in: parent).id
            } else {
                throw ProviderError.notFound
            }
        }
        return parent
    }

    private func createFolder(named name: String, in parent: String?) async throws -> GraphFolder {
        let url = GraphTransport.baseURL.appending(
            path: parent.map { "me/mailFolders/\($0)/childFolders" } ?? "me/mailFolders")
        return try await translatingFailures {
            // Sent again only when refused unread: after a server error the folder may exist, and a second create
            // would be refused as a duplicate.
            let data = try await graph.send(
                url, method: "POST", json: FolderBody(displayName: name), replay: .onlyIfRefused)
            return try JSONDecoder.graph.decode(GraphFolder.self, from: data)
        }
    }

    /// Graph's refusals as the provider's: a name taken or invalid is rejected, a folder gone is not found.
    private func translatingFailures<T>(_ body: () async throws -> T) async throws -> T {
        do {
            return try await body()
        } catch let error as GraphError where error.status == 404 {
            throw ProviderError.notFound
        } catch let error as GraphError where error.status == 400 || error.status == 409 {
            throw ProviderError.rejected
        }
    }

    /// A path's folder names. One with an empty name, as `Projects//Goodmail`, can't be made.
    static func components(of path: String) throws -> [String] {
        let names = path.split(separator: "/", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard !names.contains(where: \.isEmpty) else { throw ProviderError.rejected }
        return names
    }

    private static func folderURL(_ id: String) -> URL {
        GraphTransport.baseURL.appending(path: "me/mailFolders/\(id)")
    }
}

/// A folder's name, to create one or rename it.
private struct FolderBody: Encodable {
    let displayName: String
}

/// Where a folder moves: another folder's ID, or `msgfolderroot` for the top of the mailbox.
private struct FolderMove: Encodable {
    let destinationId: String
}
