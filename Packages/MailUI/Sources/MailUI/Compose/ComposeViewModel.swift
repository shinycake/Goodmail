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
    /// Whether the message is still being written, and how it ended once it isn't. Only the methods below move it.
    /// Not observed: it changes with every keystroke while autosave waits, and the composer is UIKit, reading
    /// `isWriting` and `canSend` as it acts rather than observing them.
    @ObservationIgnored private(set) var lifecycle = Lifecycle.writing(.untouched)
    /// Runs after each version autosave or leaving the screen keeps, for the composer's host to keep what it holds of
    /// the message in step.
    @ObservationIgnored var didKeep: (() -> Void)?
    /// How long after an edit the draft is kept on the device, so a crash loses at most that much writing.
    @ObservationIgnored private let autosavePause: Duration

    /// The message is written until it ends one way; from then on nothing sends, saves, deletes or keeps it again,
    /// even while its card is still sliding off the screen.
    enum Lifecycle {
        /// Being written, with where the draft stands with autosave.
        case writing(Autosave)
        /// Done with. A send or save that fails brings it back to `writing` (`resumeKeeping`).
        case ended(Ending)
    }

    /// How the message stopped being written.
    enum Ending: Equatable, Sendable {
        /// Queued to go, now or later.
        case sent
        /// Kept in the provider's Drafts by the writer's choice.
        case saved
        case deleted
        /// Closed with nothing changed, any version autosave kept undone.
        case closedUnchanged
        /// Moved, as written, to a window of its own, which goes on with it.
        case handedOff
    }

    /// Where the draft stands with autosave while it is written.
    enum Autosave {
        /// Nothing kept since the composer opened.
        case untouched
        /// A version was kept, which closing must settle: the writer's choice, or putting back what was opened.
        case kept
        /// An edit is waiting to be kept, as `body` reads the message when the wait ends; `hasKept` says whether an
        /// earlier version was. Later edits join the wait rather than restart it, so typing that never rests is
        /// still kept.
        case waiting(Task<Void, Never>, body: () -> MessageBody?, hasKept: Bool)

        /// Whether a version was kept, which closing unchanged must undo.
        var hasKept: Bool {
            switch self {
            case .untouched: false
            case .kept: true
            case .waiting(_, _, let hasKept): hasKept
            }
        }
    }

    /// Whether the message is still being written: everything that would send, save, delete or change it asks.
    public var isWriting: Bool {
        guard case .writing = lifecycle else { return false }
        return true
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
        deleteDraft: @escaping (Draft) -> Void = { _ in }, autosavePause: Duration = .seconds(1),
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

    /// The message is still being written, every typed recipient looks like an address, and there is at least one.
    public var canSend: Bool {
        let all = recipients.all
        return isWriting && !all.isEmpty && all.allSatisfy(\.hasValidAddress)
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

    /// How many more bytes of files the message can take.
    var attachmentRoom: Int { attachments.room }

    /// Adds the file unless it would take the message past what Gmail accepts, or the message is no longer written.
    /// Returns whether it was added.
    @discardableResult
    public func attach(_ attachment: DraftAttachment) -> Bool {
        guard isWriting else { return false }
        return attachments.attachIfRoom(attachment)
    }

    public func removeAttachment(_ id: DraftAttachment.ID) {
        guard isWriting else { return }
        attachments.removeAll { $0.id == id }
    }

    /// Queues the message with `body` as written, to go at `time`. Does nothing while `canSend` is false, so a
    /// second Send after the first does nothing. Returns whether it went.
    @discardableResult
    public func send(body: MessageBody, at time: SendTime = .now) -> Bool {
        guard canSend else { return false }
        let draft = finished(body: body)
        end(.sent)
        sendAction(draft, time)
        return true
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

    /// Keeps the message as written in the provider's Drafts. Returns whether it did: not once the message ended.
    @discardableResult
    public func saveDraft(body: MessageBody) -> Bool {
        guard isWriting else { return false }
        let draft = finished(body: body)
        end(.saved)
        saveAction?(draft, .now)
        return true
    }

    /// Throws the message away, with the provider's copy when it was opened from one or autosave kept one. Returns
    /// whether it did: not once the message ended, as after it was sent.
    @discardableResult
    public func deleteDraft() -> Bool {
        guard isWriting else { return false }
        end(.deleted)
        deleteAction(draft)
        return true
    }

    /// The message moves to a window of its own, which goes on writing it: this composer keeps nothing more. Returns
    /// the message as written, or `nil` once it ended.
    public func handOff(body: MessageBody) -> Draft? {
        guard isWriting else { return nil }
        let draft = finished(body: body)
        end(.handedOff)
        return draft
    }

    /// Something changed: the draft is kept a moment later, as `body` reads it then (`nil` once the editor is
    /// gone), if it differs from how it opened. Edits during the wait are kept with it.
    public func edited(body: @escaping () -> MessageBody?) {
        guard saveAction != nil, case .writing(let autosave) = lifecycle else { return }
        if case .waiting(let task, _, let hasKept) = autosave {
            lifecycle = .writing(.waiting(task, body: body, hasKept: hasKept))
            return
        }
        // A draft is written whole, files and all, so one carrying large files is kept less often.
        let large = attachments.reduce(0) { $0 + $1.size } > Self.largeAttachments
        let pause = large ? autosavePause * 5 : autosavePause
        let task = Task { [weak self] in
            try? await Task.sleep(for: pause)
            guard !Task.isCancelled else { return }
            self?.keepWaitingEdit()
        }
        lifecycle = .writing(.waiting(task, body: body, hasKept: autosave.hasKept))
    }

    /// The wait after an edit ended: the message is kept as it reads now.
    private func keepWaitingEdit() {
        guard case .writing(.waiting(_, let read, let hasKept)) = lifecycle else { return }
        guard let body = read() else {
            lifecycle = .writing(hasKept ? .kept : .untouched)
            return
        }
        keep(body: body, wait: .asWritten)
    }

    /// Files past this many bytes in all make autosave wait longer between versions.
    static let largeAttachments = 1_000_000

    /// The message came back to be written after its send or save failed, with nothing sent or saved: what is
    /// written from here is kept again, and closing settles it as one that was kept.
    public func resumeKeeping() {
        switch lifecycle {
        case .ended(.sent), .ended(.saved): lifecycle = .writing(.kept)
        case .writing, .ended(.deleted), .ended(.closedUnchanged), .ended(.handedOff): break
        }
    }

    /// Waits for an edit waiting to be kept.
    func settleAutosave() async {
        if case .writing(.waiting(let task, _, _)) = lifecycle { await task.value }
    }

    /// The app is leaving the screen: keeps the draft with the provider now, in case it isn't reopened.
    public func keepNow(body: MessageBody) {
        keep(body: body, wait: .leaving)
    }

    /// Keeps the draft as written, once it differs from how it opened. After a version was kept it is always kept
    /// again, so the copy follows the writer even back to how it started.
    private func keep(body: MessageBody, wait: DraftSave) {
        guard let saveAction, case .writing(let autosave) = lifecycle else { return }
        if case .waiting(let task, _, _) = autosave { task.cancel() }
        guard autosave.hasKept || hasChanges(body: body) else {
            lifecycle = .writing(.untouched)
            return
        }
        saveAction(finished(body: body), wait)
        lifecycle = .writing(.kept)
        didKeep?()
    }

    /// Closes without a change. A version autosave kept is undone: the copy it was opened from is put back, or the
    /// kept one removed. Returns whether it closed: not once the message ended another way.
    @discardableResult
    public func closeUnchanged() -> Bool {
        guard case .writing(let autosave) = lifecycle else { return false }
        end(.closedUnchanged)
        guard autosave.hasKept else { return true }
        if draft.savedDraft != nil { saveAction?(draft, .now) } else { deleteAction(draft) }
        return true
    }

    /// The one way out of writing. An edit still waiting to be kept is dropped: the ending settles the message.
    private func end(_ ending: Ending) {
        if case .writing(.waiting(let task, _, _)) = lifecycle { task.cancel() }
        lifecycle = .ended(ending)
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
