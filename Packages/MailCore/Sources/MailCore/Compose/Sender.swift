import Foundation

/// Delivers one account's queued messages, oldest first. Drafts are saved or deleted on the spot; a message to send
/// is handed to an upload that outlives the app once its undo window closes, and leaves the queue when that
/// upload's outcome comes back through `complete`. Every step is a compare-and-set on the message's delivery, so a
/// relaunch, a late outcome or an undo racing the hand-off never sends a message twice.
public actor Sender {
    public nonisolated let accountID: AccountID
    private let provider: any MailProvider
    private let store: any OutgoingStore
    private let transport: any UploadTransport
    private let files: UploadFiles
    private let now: @Sendable () -> Date
    private var running: Task<[Draft], Never>?

    /// Upload bodies are kept under `uploads`, in a folder of the account's own.
    public init(
        accountID: AccountID,
        provider: any MailProvider,
        store: any OutgoingStore,
        transport: any UploadTransport,
        uploads: URL,
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.accountID = accountID
        self.provider = provider
        self.store = store
        self.transport = transport
        files = UploadFiles(directory: uploads.appending(path: accountID.rawValue, directoryHint: .isDirectory))
        self.now = now
    }

    /// Settles uploads that ended unheard, then hands off, saves or deletes what is due. A refused message is
    /// marked failed and kept, for the writer to fix; a network failure, or an account that can't be read, leaves it
    /// queued for the next call. Returns what went: drafts saved or deleted now, and sends confirmed while settling.
    @discardableResult
    public func flush() async -> [Draft] {
        if let running { return await running.value }
        let task = Task { await drain() }
        running = task
        defer { running = nil }
        return await task.value
    }

    /// Takes in how upload `id` ended. Returns the draft when its message went. An outcome for an attempt that is
    /// no longer current, such as one reported twice, changes nothing.
    public func complete(_ id: UploadID, with outcome: UploadOutcome) async -> Draft? {
        defer { files.remove(id) }
        guard let message = try? store.uploadingMessages(for: accountID).first(where: { $0.delivery == .uploading(id) })
        else { return nil }
        guard case .upload(let uploads) = provider.sending else { return nil }
        guard case .response(let status, let body) = outcome else {
            return await settleUnanswered(message, id, with: uploads)
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
            return await settleUnanswered(message, id, with: uploads)
        }
        guard (try? store.update(message.id, from: .uploading(id), to: next)) == true, next == nil else { return nil }
        await deleteSavedCopy(of: message.draft)
        return message.draft
    }

    private enum Step {
        case next
        case took(Draft)
        case stop
    }

    private func drain() async -> [Draft] {
        var taken = await settleUploads()
        while let message = (try? store.dueMessages(for: accountID, by: now()))?.first {
            switch await attempt(message) {
            case .next: continue
            case .took(let draft): taken.append(draft)
            case .stop: return taken
            }
        }
        return taken
    }

    private func attempt(_ message: OutgoingMessage) async -> Step {
        let draft: Draft
        do {
            draft = try await fetchingForwardedFiles(of: message.draft)
        } catch ProviderError.notFound {
            _ = try? store.update(message.id, from: .queued, to: message.with(.failed(.forwardedAttachmentMissing)))
            return .next
        } catch {
            return .stop
        }
        // Read as each message goes, so a renamed account's next message carries the new name.
        guard let from = try? store.sender(for: accountID) else { return .stop }
        let raw = MIMEWriter.message(for: draft, from: from, date: now(), messageID: message.headerID)
        do {
            switch message.purpose {
            case .send, .scheduledSend:
                switch provider.sending {
                case .direct(let send):
                    try await send(raw, draft.threadID)
                    await deleteSavedCopy(of: draft)
                case .upload(let uploads):
                    try await handOff(message, raw: raw, via: uploads)
                    return .next
                }
            case .saveDraft:
                try await provider.saveDraft(raw, inThread: draft.threadID, replacing: draft.savedDraft)
            case .deleteDraft:
                if let saved = draft.savedDraft { try await provider.deleteDraft(saved) }
            }
            _ = try store.update(message.id, from: .queued, to: nil)
            return .took(message.draft)
        } catch ProviderError.rejected {
            _ = try? store.update(message.id, from: .queued, to: message.with(.failed(.rejected)))
            return .next
        } catch ProviderError.notFound {
            // The thread is gone; save it on its own.
            var alone = message
            alone.draft.threadID = nil
            _ = try? store.update(message.id, from: .queued, to: alone)
            return .next
        } catch {
            return .stop
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
            _ = try? store.update(message.id, from: .uploading(id), to: message)
            throw error
        }
    }

    /// Resolves messages whose upload the transport no longer has and whose outcome never came, then clears
    /// files no upload needs. Returns the drafts found to have gone.
    private func settleUploads() async -> [Draft] {
        guard case .upload(let uploads) = provider.sending else { return [] }
        let active = await transport.activeUploads()
        var sent: [Draft] = []
        for message in (try? store.uploadingMessages(for: accountID)) ?? [] {
            guard case .uploading(let id) = message.delivery, !active.contains(id) else { continue }
            if let draft = await settleUnanswered(message, id, with: uploads) { sent.append(draft) }
        }
        let uploading = ((try? store.uploadingMessages(for: accountID)) ?? []).compactMap { message in
            if case .uploading(let id) = message.delivery { id } else { nil }
        }
        files.removeAll(except: Set(uploading))
        return sent
    }

    /// An upload that ended without an answer may still have delivered the message, so the provider is asked.
    /// Found: it went. Not found: it fails as unconfirmed, for the writer to send again, since sending it unasked
    /// could send it twice. Asking fails: it stays uploading, to ask on the next flush.
    private func settleUnanswered(_ message: OutgoingMessage, _ id: UploadID, with uploads: any UploadSending) async
        -> Draft?
    {
        files.remove(id)
        guard let went = try? await uploads.hasSent(messageID: message.headerID) else { return nil }
        let next = went ? nil : message.with(.failed(.unconfirmed))
        guard (try? store.update(message.id, from: .uploading(id), to: next)) == true, went else { return nil }
        await deleteSavedCopy(of: message.draft)
        return message.draft
    }

    /// A saved copy left behind is only a stale draft, not worth failing a sent message over.
    private func deleteSavedCopy(of draft: Draft) async {
        if let saved = draft.savedDraft { try? await provider.deleteDraft(saved) }
    }

    private func fetchingForwardedFiles(of draft: Draft) async throws -> Draft {
        var draft = draft
        for index in draft.attachments.indices {
            if case .forwarded(let attachment, let message) = draft.attachments[index].content {
                draft.attachments[index].content = .data(try await provider.data(for: attachment, in: message))
            }
        }
        return draft
    }
}
