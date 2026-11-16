/// Renaming and deleting a step of nested labels' paths that is no label itself, as `Extra` is when Gmail has only
/// `Extra/Unsubscribed`. The step holds no mail and has no ID, so the change goes to each label under it.
extension SyncEngine {
    /// Deletes every user label under the path `path` at the service, as deleting a label deletes the labels nested
    /// in it, then stores what the service did, even when it failed partway.
    public func deleteLabels(under path: String) async throws {
        let nested = try store.labels(for: accountID).nested(under: path)
        try await deleteLabels(nested.outermost.map(\.id), carrying: Set(nested.map(\.id)))
    }

    /// Moves every user label under the path `path` to `name`, as `Extra/Unsubscribed` becomes
    /// `Archive/Unsubscribed`, then stores what the service did, even when it refused a name partway.
    public func renameLabels(under path: String, to name: String) async throws {
        guard name != path else { return }
        let outermost = try store.labels(for: accountID).nested(under: path).outermost
        try await storingLabels {
            // Each service renames the labels nested in a label with it.
            for label in outermost {
                try await provider.renameLabel(label.id, to: name + label.name.dropFirst(path.count))
            }
        }
    }

    /// Deletes the user labels `ids` at the service, then stores the account's labels and refetches the threads that
    /// carried any of `doomed`: the service may move or remove their mail without reporting it changed.
    func deleteLabels(_ ids: [String], carrying doomed: Set<String>) async throws {
        let affected = try store.threadIDs(labeled: doomed, account: accountID)
        var failure: (any Error)?
        do {
            try await storingLabels { for id in ids { try await provider.deleteLabel(id) } }
        } catch {
            failure = error
        }
        // Refetched even after a failure, since the labels deleted before it may have taken mail along.
        if !affected.isEmpty {
            let fetchedAt = now()
            let fetch = try await provider.threads(withIDs: affected.sorted())
            try store.apply(
                StoreChanges(accountID: accountID, upserts: fetch.found, deletions: fetch.missing, fetchedAt: fetchedAt)
            )
        }
        if let failure { throw failure }
    }

    /// Runs `change` at the service, then stores the account's labels, which a change that failed partway left
    /// changed too. The change's failure wins over the read's.
    private func storingLabels(_ change: () async throws -> Void) async throws {
        do {
            try await change()
        } catch {
            try? await refreshLabels()
            throw error
        }
        try await refreshLabels()
    }
}

extension [MailLabel] {
    /// The user labels whose paths run under `path`, as `Extra/Unsubscribed` does under `Extra`, but not `Extras`.
    func nested(under path: String) -> [MailLabel] {
        filter { $0.kind == .user && $0.name.hasPrefix(path + "/") }
    }

    /// The labels that no other of these holds, which take the rest with them when renamed or deleted.
    var outermost: [MailLabel] {
        filter { label in !contains { label.name.hasPrefix($0.name + "/") } }
    }
}
