public import Foundation
public import MailCore
public import Observation

/// A message being written: its recipients, subject and body, and whether it can go.
@Observable
public final class ComposeViewModel {
    public private(set) var draft: Draft
    /// The address of the account the message goes from.
    public private(set) var accountEmail: String
    /// The accounts the message can go from, with their aliases.
    public let senders: [Account]
    /// The To, Cc and Bcc fields as the writer edits them: tokens, then what is still being typed.
    public var recipients: Recipients
    public var subject: String
    /// The files going with the message.
    public private(set) var attachments: [DraftAttachment]
    @ObservationIgnored private let sendAction: (Draft, SendTime) -> Void
    @ObservationIgnored private let saveAction: ((Draft, DraftSave) -> Void)?
    @ObservationIgnored private let deleteAction: (Draft) -> Void
    @ObservationIgnored private let signature: (AccountID) -> String?
    /// What another app shared, which a new message starts with, between the line being written and the signature.
    @ObservationIgnored private let shared: String
    @ObservationIgnored private let suggest: (String) async -> [Contact]
    /// A draft that comes back with text, after Undo or a failed send, holds work closing would lose.
    @ObservationIgnored let isRestored: Bool
    @ObservationIgnored private var autosave: Autosave = .untouched
    /// How long typing rests before the draft is kept on the device.
    @ObservationIgnored private let autosavePause: Duration

    /// Where the draft stands with autosave. Only the methods below move it.
    private enum Autosave {
        /// Nothing kept since the composer opened.
        case untouched
        /// A version was kept, which closing must settle: the writer's choice, or putting back what was opened.
        case kept
        /// An edit is waiting for typing to rest, then is kept; `hasKept` says whether an earlier version was.
        case waiting(Task<Void, Never>, hasKept: Bool)
        /// The composer is closing; nothing more is kept.
        case closed
    }

    /// `send` queues the finished draft to go now or later; the composer closes right after. `saveDraft` keeps it in
    /// the provider's Drafts, now or, as autosave does while it is written, after a wait; `deleteDraft` removes the copy
    /// it was opened from or autosave left. `suggest` finds people for what is typed. A new
    /// draft starts with the text another app `shared`, if any, then its account's `signature`, below the line being
    /// written.
    public init(
        draft: Draft, accountEmail: String, senders: [Account] = [], shared: String = "",
        signature: @escaping (AccountID) -> String? = { _ in nil },
        suggest: @escaping (String) async -> [Contact] = { _ in [] }, saveDraft: ((Draft, DraftSave) -> Void)? = nil,
        deleteDraft: @escaping (Draft) -> Void = { _ in }, autosavePause: Duration = .seconds(2),
        send: @escaping (Draft, SendTime) -> Void
    ) {
        self.autosavePause = autosavePause
        let isNew = (draft.body.plain ?? "").isEmpty
        // A draft opened from the provider's Drafts is safe there until it changes.
        isRestored = !isNew && draft.savedDraft == nil
        var draft = draft
        if isNew { draft.body = Self.startingBody(shared: shared, signature: signature(draft.accountID)) }
        self.draft = draft
        self.accountEmail = accountEmail
        self.senders = senders
        self.shared = shared
        self.signature = signature
        recipients = Recipients(to: draft.to, cc: draft.cc, bcc: draft.bcc)
        subject = draft.subject
        attachments = draft.attachments
        sendAction = send
        saveAction = saveDraft
        deleteAction = deleteDraft
        self.suggest = suggest
    }

    /// Every typed recipient looks like an address, and there is at least one.
    public var canSend: Bool {
        let all = recipients.all
        return !all.isEmpty && all.allSatisfy(\.hasValidAddress)
    }

    public var isReply: Bool { draft.inReplyTo != nil }

    /// Whether closing would lose anything the writer did, formatting included.
    public func hasChanges(body: MessageBody) -> Bool {
        let edited = finished(body: body)
        return isRestored || edited.to != draft.to || edited.cc != draft.cc || edited.bcc != draft.bcc
            || edited.subject != draft.subject || RichText(body) != RichText(draft.body)
            || edited.attachments != draft.attachments
    }

    /// Gmail refuses messages over 25 MB, and encoding the files adds a third.
    public static let attachmentLimit = 18_000_000

    /// Adds the file unless it would take the message past what Gmail accepts. Returns whether it was added.
    @discardableResult
    public func attach(_ attachment: DraftAttachment) -> Bool {
        guard attachments.reduce(attachment.size, { $0 + $1.size }) <= Self.attachmentLimit else {
            return false
        }
        attachments.append(attachment)
        return true
    }

    public func removeAttachment(_ id: DraftAttachment.ID) {
        attachments.removeAll { $0.id == id }
    }

    /// Queues the message with `body` as written, to go at `time`. Does nothing while `canSend` is false.
    public func send(body: MessageBody, at time: SendTime = .now) {
        guard canSend else { return }
        close()
        sendAction(finished(body: body), time)
    }

    public var canSaveDraft: Bool { saveAction != nil }

    /// The addresses the message can go from: any account's or alias for new mail; a reply, forward or saved
    /// draft stays in its own account.
    public var senderChoices: [SendingAddress] { SendingAddress.choices(for: draft, among: senders) }

    public var canChangeSender: Bool { senderChoices.count > 1 }

    /// The address the message goes from: its alias, else its account's own.
    public var fromAddress: String { draft.alias?.address ?? accountEmail }

    /// Sends from `address` instead. While the body is still as it started, its signature follows a change of
    /// account: returns the new body to show then, `nil` when the body stays.
    public func changeSender(to address: SendingAddress, body: MessageBody) -> MessageBody? {
        let untouched = RichText(body) == RichText(draft.body)
        let changesAccount = address.account.id != draft.accountID
        draft.accountID = address.account.id
        draft.alias = address.alias
        accountEmail = address.account.email
        guard changesAccount, untouched else { return nil }
        draft.body = Self.startingBody(shared: shared, signature: signature(address.account.id))
        return draft.body
    }

    private static func startingBody(shared: String, signature: String?) -> MessageBody {
        var plain = shared.isEmpty ? "" : "\n\n" + shared
        if let signature, !signature.isEmpty { plain += "\n\n-- \n" + signature }
        return plain.isEmpty ? MessageBody(html: "", plain: "") : MessageBody(html: nil, plain: plain)
    }

    /// Keeps the message as written in the provider's Drafts.
    public func saveDraft(body: MessageBody) {
        close()
        saveAction?(finished(body: body), .now)
    }

    /// Throws the message away, with the provider's copy when it was opened from one or autosave kept one.
    public func deleteDraft() {
        close()
        deleteAction(draft)
    }

    /// Something changed: once typing rests, the draft is kept, if it differs from how it opened. `body` reads it
    /// as it is then, `nil` once the editor is gone.
    public func edited(body: @escaping () -> MessageBody?) {
        guard saveAction != nil else { return }
        let pause = autosavePause
        let task = Task { [weak self] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled, let body = body() else { return }
            self?.keep(body: body, wait: .asWritten)
        }
        switch autosave {
        case .closed: task.cancel()
        case .untouched: autosave = .waiting(task, hasKept: false)
        case .kept: autosave = .waiting(task, hasKept: true)
        case .waiting(let earlier, let hasKept):
            earlier.cancel()
            autosave = .waiting(task, hasKept: hasKept)
        }
    }

    /// Waits for an edit waiting to be kept.
    func settleAutosave() async {
        if case .waiting(let task, _) = autosave { await task.value }
    }

    /// The app is leaving the screen: keeps the draft with the provider now, in case it isn't reopened.
    public func keepNow(body: MessageBody) {
        keep(body: body, wait: .leaving)
    }

    /// Keeps the draft as written, once it differs from how it opened. After a version was kept it is always kept
    /// again, so the copy follows the writer even back to how it started.
    private func keep(body: MessageBody, wait: DraftSave) {
        guard let saveAction else { return }
        let hasKept: Bool
        switch autosave {
        case .closed: return
        case .untouched: hasKept = false
        case .kept: hasKept = true
        case .waiting(let task, let kept):
            task.cancel()
            hasKept = kept
        }
        guard hasKept || hasChanges(body: body) else {
            autosave = .untouched
            return
        }
        saveAction(finished(body: body), wait)
        autosave = .kept
    }

    /// Closes without a change. A version autosave kept is undone: the copy it was opened from is put back, or the
    /// kept one removed.
    public func closeUnchanged() {
        let hasKept =
            switch autosave {
            case .kept, .waiting(_, hasKept: true): true
            case .untouched, .waiting, .closed: false
            }
        close()
        guard hasKept else { return }
        if draft.savedDraft != nil { saveAction?(draft, .now) } else { deleteAction(draft) }
    }

    private func close() {
        if case .waiting(let task, _) = autosave { task.cancel() }
        autosave = .closed
    }

    func finished(body: MessageBody) -> Draft {
        var draft = draft
        draft.to = recipients.to.all
        draft.cc = recipients.cc.all
        draft.bcc = recipients.bcc.all
        draft.subject = subject
        draft.body = body
        draft.attachments = attachments
        return draft
    }

    /// People to offer for what is typed in the `role` field, leaving out those already in it and the addresses the
    /// message can go from.
    public func suggestions(for role: Recipients.Role) async -> [Contact] {
        let entry = recipients[role]
        let typed = entry.typed.trimmingCharacters(in: .whitespaces)
        guard !typed.isEmpty else { return [] }
        let excluded = Set(
            (entry.contacts.map(\.address) + senders.flatMap { [$0.email] + $0.aliases.map(\.address) }
                + [accountEmail]).map { $0.lowercased() })
        return await suggest(typed).filter { !excluded.contains($0.address.lowercased()) }
    }
}

/// When a draft goes to the provider's Drafts.
public enum DraftSave: Sendable {
    /// Now, as when the writer chose Save Draft.
    case now
    /// Now, without the writer asking, as the app leaves the screen with the message open.
    case leaving
    /// After a wait, as autosave keeps it while it is written: kept on the device at once, sent on once per wait.
    case asWritten
}
