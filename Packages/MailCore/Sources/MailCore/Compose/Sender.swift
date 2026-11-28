public import Foundation

/// Delivers one account's queued messages, oldest first. Drafts are saved or deleted on the spot; a message to send
/// is handed to an upload that outlives the app once its undo window closes, and leaves the queue when that
/// upload's outcome comes back through `complete`. Every step is a compare-and-set on the message's delivery, so a
/// relaunch, a late outcome or an undo racing the hand-off never sends a message twice. One per account, so its
/// drains never overlap.
public actor Sender {
    public nonisolated let accountID: AccountID
    /// The account's provider, read as each drain, outcome or preparation begins, so a new sign-in sends from then on.
    private let provider: @Sendable () throws -> any MailProvider
    private let store: any OutgoingStore
    private let transport: any UploadTransport
    private let files: UploadFiles
    private let now: @Sendable () -> Date
    private let log: MailLog
    private var running: Task<[Draft], Never>?
    /// Messages that went but are still queued, because taking them out of the queue failed, as it does while the
    /// database is suspended. Never sent again; taken out at the start of each drain. Held in memory alone: the write
    /// that would record it is the one that failed.
    private var sentButQueued: Set<Draft.ID> = []

    /// Upload bodies are kept under `uploads`, in a folder of the account's own. Reads and writes of the queue that
    /// fail are recorded in `log`.
    public init(
        accountID: AccountID,
        provider: @escaping @Sendable () throws -> any MailProvider,
        store: any OutgoingStore,
        transport: any UploadTransport,
        uploads: URL,
        now: @escaping @Sendable () -> Date = { .now },
        log: MailLog = MailLog(category: "outgoing")
    ) {
        self.accountID = accountID
        self.provider = provider
        self.store = store
        self.transport = transport
        files = UploadFiles(directory: uploads.appending(path: accountID.rawValue, directoryHint: .isDirectory))
        self.now = now
        self.log = log
    }

    public init(
        accountID: AccountID,
        provider: any MailProvider,
        store: any OutgoingStore,
        transport: any UploadTransport,
        uploads: URL,
        now: @escaping @Sendable () -> Date = { .now },
        log: MailLog = MailLog(category: "outgoing")
    ) {
        self.init(
            accountID: accountID, provider: { provider }, store: store, transport: transport, uploads: uploads,
            now: now, log: log)
    }

    /// Settles uploads that ended unheard, then hands off, saves or deletes what is due. A refused message is
    /// marked failed and kept, for the writer to fix; a network failure, an account that can't be read, or a queue
    /// that can't be read or written leaves it queued for the next call. Returns what went: drafts saved or deleted
    /// now, and sends confirmed while settling.
    @discardableResult
    public func flush() async -> [Draft] {
        if let running { return await running.value }
        let task = Task { await drain() }
        running = task
        defer { running = nil }
        return await task.value
    }

    /// Settles uploads that ended unheard, as `flush` does first, without sending anything due: as when the watch
    /// gives a reply back and needs to know first whether it went. Returns the drafts found to have gone.
    @discardableResult
    public func settle() async -> [Draft] {
        if let running { _ = await running.value }
        guard let provider = try? self.provider() else { return [] }
        return await settleUploads(on: provider)
    }

    /// Gets the provider ready for a message due soon, as by logging in while its undo window runs. Returns without
    /// waiting for that.
    public func prepare() async {
        guard case .direct(let direct) = try? provider().sending else { return }
        await direct.prepareToSend()
    }

    /// Takes in how upload `id` ended. Returns the draft when its message went. An outcome for an attempt that is
    /// no longer current, such as one reported twice, changes nothing.
    public func complete(_ id: UploadID, with outcome: UploadOutcome) async -> Draft? {
        defer { files.remove(id) }
        // A queue that can't be read leaves the message uploading, for `settleUploads` to ask about.
        guard let message = uploadingMessages()?.first(where: { $0.delivery == .uploading(id) }) else { return nil }
        guard let provider = try? self.provider(), case .upload(let uploads) = provider.sending else { return nil }
        guard case .response(let status, let body) = outcome else {
            return await settleUnanswered(message, id, with: uploads, on: provider)
        }
        let next: OutgoingMessage?
        switch uploads.answer(status: status, body: body) {
        case .sent:
            next = nil
        case .rejected:
            next = message.with(.failed(.rejected))
        case .threadGone:
            // The thread is gone; send it on its own.
            var alone = message.with(.queued)
            alone.draft.threadID = nil
            next = alone
        case .turnedAway:
            next = message.with(.queued)
        case .unknown:
            return await settleUnanswered(message, id, with: uploads, on: provider)
        }
        guard moved(message, from: .uploading(id), to: next), next == nil else { return nil }
        await deleteSavedCopy(of: message.draft, on: provider)
        return message.draft
    }

    private enum Step {
        case next
        case took(Draft)
        /// It went, and nothing more goes on this drain.
        case tookLast(Draft)
        case stop
    }

    private func drain() async -> [Draft] {
        // An account whose sign-in can't be read keeps its mail queued for the next flush.
        guard let provider = try? self.provider() else { return [] }
        var taken = await settleUploads(on: provider)
        guard dequeueSent() else { return taken }
        while true {
            let due: [OutgoingMessage]
            do {
                due = try store.dueMessages(for: accountID, by: now())
            } catch {
                log.error("The outgoing queue couldn't be read, so its mail waits for the next flush", error)
                return taken
            }
            guard let message = due.first else { return taken }
            let step = await Signpost.send.measure(accountID.rawValue) { await attempt(message, on: provider) }
            switch step {
            case .next: continue
            case .took(let draft): taken.append(draft)
            case .tookLast(let draft): return taken + [draft]
            case .stop: return taken
            }
        }
    }

    /// Takes out of the queue the messages that went while it couldn't be written. Returns whether none is left, so
    /// the queue's first due message is one that hasn't gone.
    private func dequeueSent() -> Bool {
        for id in sentButQueued {
            do {
                _ = try store.update(id, from: .queued, to: nil)
                sentButQueued.remove(id)
            } catch {
                log.error("A message that went still couldn't leave the queue, so nothing goes until it does", error)
                return false
            }
        }
        return true
    }

    private func attempt(_ message: OutgoingMessage, on provider: any MailProvider) async -> Step {
        let draft: Draft
        do {
            draft = try await fetchingForwardedFiles(of: message.draft, from: provider)
        } catch ProviderError.notFound {
            return requeue(message, as: message.with(.failed(.forwardedAttachmentMissing)))
        } catch {
            return .stop
        }
        // Read as each message goes, so a renamed account's next message carries the new name.
        let account: Contact
        do {
            account = try store.sender(for: accountID)
        } catch {
            log.error("Who the account's mail is from couldn't be read, so its mail waits", error)
            return .stop
        }
        let raw = MIMEWriter.message(
            for: draft, from: draft.sender(account: account), date: now(), messageID: message.headerID)
        do {
            switch message.purpose {
            case .send, .scheduledSend:
                switch provider.sending {
                case .direct(let direct):
                    try await direct.send(raw, inThread: draft.threadID)
                    // Out of the queue first, so it shows as sent while its copy is filed and its draft removed. A
                    // queue that can't be written still holds it as due: it is remembered as gone, and the drain
                    // stops, since the next message's steps couldn't be written either.
                    let dequeued: Bool
                    do {
                        _ = try store.update(message.id, from: .queued, to: nil)
                        dequeued = true
                    } catch {
                        log.fault("A message went but couldn't leave the queue; it is held as gone", error)
                        sentButQueued.insert(message.id)
                        dequeued = false
                    }
                    await direct.fileSent(raw, inThread: draft.threadID)
                    await deleteSavedCopy(of: draft, on: provider)
                    return dequeued ? .took(message.draft) : .tookLast(message.draft)
                case .upload(let uploads):
                    try await handOff(message, raw: raw, via: uploads)
                    return .next
                }
            case .saveDraft:
                let copy = try await provider.saveDraft(
                    raw, inThread: draft.threadID, replacing: try savedCopy(of: draft))
                try store.setSavedCopy(copy, of: draft.id)
                // A newer save that replaced this one while it went stays queued, and goes next.
                guard try store.finish(message) else { return .next }
                return .took(message.draft)
            case .deleteDraft:
                if let saved = try savedCopy(of: draft) { try await provider.deleteDraft(saved) }
                try store.setSavedCopy(nil, of: draft.id)
            }
            _ = try store.update(message.id, from: .queued, to: nil)
            return .took(message.draft)
        } catch ProviderError.rejected {
            return requeue(message, as: message.with(.failed(.rejected)))
        } catch ProviderError.notFound {
            // The thread is gone; save it on its own.
            var alone = message
            alone.draft.threadID = nil
            return requeue(message, as: alone)
        } catch {
            return .stop
        }
    }

    /// Writes what a queued message that didn't go becomes, and goes on to the next. A write that fails stops the
    /// drain: the message is still due as it was, so going on would only try it again, and again.
    private func requeue(_ message: OutgoingMessage, as next: OutgoingMessage) -> Step {
        do {
            _ = try store.update(message.id, from: .queued, to: next)
            return .next
        } catch {
            log.error("A message that didn't go couldn't be marked so, so its mail waits for the next flush", error)
            return .stop
        }
    }

    /// Writes an uploading message's next step, as `OutgoingStore.update` does. A write that fails leaves it
    /// uploading, for `settleUploads` to resolve on a later flush. Returns whether it moved.
    private func moved(_ message: OutgoingMessage, from expected: OutgoingMessage.Delivery, to next: OutgoingMessage?)
        -> Bool
    {
        do {
            return try store.update(message.id, from: expected, to: next)
        } catch {
            log.error("An upload's outcome couldn't be written, so it is settled on a later flush", error)
            return false
        }
    }

    /// The messages handed to an upload, or `nil` when the queue can't be read.
    private func uploadingMessages() -> [OutgoingMessage]? {
        do {
            return try store.uploadingMessages(for: accountID)
        } catch {
            log.error("The uploads under way couldn't be read, so they are settled on a later flush", error)
            return nil
        }
    }

    /// Writes the message's upload and hands it over. It is marked uploading before the upload starts, so a launch
    /// that dies in between leaves an upload that never began, which `settleUploads` resolves, never a second one.
    private func handOff(_ message: OutgoingMessage, raw: Data, via uploads: any UploadSending) async throws {
        let prepared = try await uploads.prepareSend(raw, inThread: message.draft.threadID)
        let id = UploadID()
        let file = try files.write(prepared.body, for: id)
        guard try store.update(message.id, from: .queued, to: message.with(.uploading(id))) else {
            // Taken back while it was being prepared.
            files.remove(id)
            return
        }
        do {
            try await transport.upload(prepared.request, from: file, ticket: UploadTicket(accountID: accountID, id: id))
        } catch {
            files.remove(id)
            _ = moved(message, from: .uploading(id), to: message)
            throw error
        }
    }

    /// Resolves messages whose upload the transport no longer has and whose outcome never came, then clears
    /// files no upload needs. Returns the drafts found to have gone.
    private func settleUploads(on provider: any MailProvider) async -> [Draft] {
        guard case .upload(let uploads) = provider.sending else { return [] }
        let active = await transport.activeUploads()
        guard let messages = uploadingMessages() else { return [] }
        var sent: [Draft] = []
        for message in messages {
            guard case .uploading(let id) = message.delivery, !active.contains(id) else { continue }
            if let draft = await settleUnanswered(message, id, with: uploads, on: provider) { sent.append(draft) }
        }
        // Only a queue that was read says which files are needed; clearing against one that wasn't would take them
        // all, the files of uploads under way among them.
        guard let left = uploadingMessages() else { return sent }
        let uploading = left.compactMap { message in
            if case .uploading(let id) = message.delivery { id } else { nil }
        }
        files.removeAll(except: Set(uploading))
        return sent
    }

    /// An upload that ended without an answer may still have delivered the message, so the provider is asked.
    /// Found: it went. Not found: it fails as unconfirmed, for the writer to send again, since sending it unasked
    /// could send it twice. Asking fails: it stays uploading, to ask on the next flush.
    private func settleUnanswered(
        _ message: OutgoingMessage, _ id: UploadID, with uploads: any UploadSending, on provider: any MailProvider
    ) async -> Draft? {
        files.remove(id)
        guard let went = try? await uploads.hasSent(message) else { return nil }
        let next = went ? nil : message.with(.failed(.unconfirmed))
        guard moved(message, from: .uploading(id), to: next), went else { return nil }
        await deleteSavedCopy(of: message.draft, on: provider)
        return message.draft
    }

    /// The provider's copy of `draft`: the one this device saved last, else the one it was opened from.
    private func savedCopy(of draft: Draft) throws -> Message.ID? {
        try store.savedCopy(of: draft.id) ?? draft.savedDraft
    }

    /// A saved copy left behind is only a stale draft, not worth failing a sent message over.
    private func deleteSavedCopy(of draft: Draft, on provider: any MailProvider) async {
        do {
            guard let saved = try savedCopy(of: draft) else { return }
            try? await provider.deleteDraft(saved)
            try store.setSavedCopy(nil, of: draft.id)
        } catch {
            log.error("A sent message's saved draft couldn't be looked up or forgotten", error)
        }
    }

    private func fetchingForwardedFiles(of draft: Draft, from provider: any MailProvider) async throws -> Draft {
        var draft = draft
        for index in draft.attachments.indices {
            switch draft.attachments[index].content {
            case .data: continue
            case .forwarded(let attachment, let message):
                draft.attachments[index].content = .data(try await provider.data(for: attachment, in: message))
            case .message(let message, _):
                draft.attachments[index].content = .data(try await provider.source(of: message))
            }
        }
        return draft
    }
}

extension Signpost {
    /// One queued message's attempt, from taking it off the queue to it going out, or failing to.
    static let send = Signpost("Send")
}
