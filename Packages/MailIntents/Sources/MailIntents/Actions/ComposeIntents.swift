public import AppIntents
public import Foundation
import MailCore
import UniformTypeIdentifiers

/// Sends a new email without opening Goodmail, now or at a set time, as the composer's Send and Send Later do.
public struct SendEmailIntent: AppIntent {
    public static let title: LocalizedStringResource = "Send Email"
    public static let description = IntentDescription(
        "Sends an email from one of your accounts without opening Goodmail, now or at the time you choose.")

    @Parameter(title: "To")
    public var to: [IntentPerson]
    @Parameter(title: "CC")
    public var cc: [IntentPerson]?
    @Parameter(title: "BCC")
    public var bcc: [IntentPerson]?
    @Parameter(title: "Subject")
    public var subject: String?
    @Parameter(title: "Body", inputOptions: String.IntentInputOptions(multiline: true))
    public var body: String?
    @Parameter(title: "Attachments")
    public var attachments: [IntentFile]?
    @Parameter(title: "From", description: "The account it goes from. The first account when none is chosen.")
    public var account: AccountEntity?
    @Parameter(title: "Send At", description: "When it goes. It goes now when no time is chosen.")
    public var sendAt: Date?

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Send \(\.$body) to \(\.$to)") {
            \.$subject
            \.$cc
            \.$bcc
            \.$attachments
            \.$account
            \.$sendAt
        }
    }

    public func perform() async throws -> some IntentResult {
        let catalog = Catalog(host: host)
        let draft = try catalog.newDraft(
            WrittenMail(
                to: to.recipients, cc: cc.recipients, bcc: bcc.recipients, subject: subject, text: body ?? "",
                attachments: attachments.drafted), from: account?.id)
        try await catalog.send(draft, at: sendAt)
        return .result()
    }
}

/// Answers a message as Reply, Reply All or Forward do: sends the answer, or opens it in the composer to finish.
public struct AnswerMessageIntent: AppIntent {
    public static let title: LocalizedStringResource = "Reply to Message"
    public static let description = IntentDescription(
        "Replies to a message, to its sender or to everyone on it, or forwards it. Sends the answer, or opens it in the composer."
    )
    public static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "Message")
    public var message: MessageEntity
    @Parameter(title: "Answer", default: .reply)
    public var answer: AnswerKind
    @Parameter(title: "Body", inputOptions: String.IntentInputOptions(multiline: true))
    public var body: String?
    @Parameter(title: "To", description: "Who a forward goes to, or more people for a reply.")
    public var to: [IntentPerson]?
    @Parameter(title: "CC")
    public var cc: [IntentPerson]?
    @Parameter(title: "Attachments")
    public var attachments: [IntentFile]?
    @Parameter(
        title: "Open in Composer", description: "Opens the answer in Goodmail to finish instead of sending it.",
        default: false)
    public var opensComposer: Bool
    @Parameter(title: "Send At", description: "When it goes. It goes now when no time is chosen.")
    public var sendAt: Date?

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$opensComposer, .equalTo, true) {
            Summary("\(\.$answer) \(\.$message) in the composer, with \(\.$body)") {
                \.$opensComposer
                \.$to
                \.$cc
                \.$attachments
            }
        } otherwise: {
            Summary("\(\.$answer) \(\.$message) with \(\.$body)") {
                \.$opensComposer
                \.$to
                \.$cc
                \.$attachments
                \.$sendAt
            }
        }
    }

    public func perform() async throws -> some IntentResult {
        let catalog = Catalog(host: host)
        let draft = try await catalog.answer(
            answer.answer, toMessage: message.id,
            with: WrittenMail(to: to.recipients, cc: cc.recipients, text: body ?? "", attachments: attachments.drafted))
        if opensComposer {
            try await continueInForeground(alwaysConfirm: false)
            await host.open(.compose(draft))
        } else {
            try await catalog.send(draft, at: sendAt)
        }
        return .result()
    }
}

/// How a message is answered, as Shortcuts offers it.
public enum AnswerKind: String, AppEnum {
    case reply, replyAll, forward, forwardAsAttachment

    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Answer"
    public static let caseDisplayRepresentations: [AnswerKind: DisplayRepresentation] = [
        .reply: DisplayRepresentation(title: "Reply", image: .init(systemName: "arrowshape.turn.up.left")),
        .replyAll: DisplayRepresentation(title: "Reply All", image: .init(systemName: "arrowshape.turn.up.left.2")),
        .forward: DisplayRepresentation(title: "Forward", image: .init(systemName: "arrowshape.turn.up.right")),
        .forwardAsAttachment: DisplayRepresentation(
            title: "Forward as Attachment", image: .init(systemName: "paperclip")),
    ]

    var answer: Answer {
        switch self {
        case .reply: .reply
        case .replyAll: .replyAll
        case .forward: .forward
        case .forwardAsAttachment: .forwardAsAttachment
        }
    }
}

extension Catalog {
    /// The account with the identifier, or the first account when none is given. `nil` when it's gone or there is
    /// none.
    func account(_ identifier: String?) throws -> Account? {
        let accounts = try host.accounts()
        return identifier.map { id in accounts.first { $0.id.rawValue == id } } ?? accounts.first
    }

    /// A new message with what was written, from the account with the identifier or else the first.
    func newDraft(_ mail: WrittenMail, from account: String?) throws -> Draft {
        guard let account = try self.account(account) else { throw IntentError.gone }
        var draft = Draft(accountID: account.id)
        do { try draft.add(mail) } catch { throw IntentError(error) }
        return draft
    }

    /// The answer to the message with the identifier, with what was written added to it.
    func answer(_ answer: Answer, toMessage identifier: String, with mail: WrittenMail) async throws -> Draft {
        guard let id = EntityID.message(identifier),
            var draft = try await host.answer(answer, to: id.message, inThread: id.thread)
        else { throw IntentError.gone }
        do { try draft.add(mail) } catch { throw IntentError(error) }
        return draft
    }

    /// Sends the draft now, or at `date`, once it has someone to go to.
    func send(_ draft: Draft, at date: Date?) async throws {
        do { try draft.checkReadyToSend() } catch { throw IntentError(error) }
        try await host.send(draft, at: date)
    }
}

extension IntentPerson {
    /// The person as a recipient is typed: `Name <address>`, or the bare address or text Shortcuts passed.
    var recipient: String {
        let address =
            switch handle?.value {
            case .emailAddress(let address), .applicationDefined(let address): address
            case .phoneNumber(let number): number
            case nil:
                switch identifier {
                case .applicationDefined(let text), .contact(let text): text
                case .unknown: ""
                @unknown default: ""
                }
            @unknown default: ""
            }
        guard case .displayName(let name) = self.name, !name.isEmpty, name != address else { return address }
        return Contact(name: name, address: address).typedForm
    }
}

extension Optional where Wrapped == [IntentPerson] {
    var recipients: [String] { (self ?? []).map(\.recipient) }
}

extension Array where Element == IntentPerson {
    var recipients: [String] { map(\.recipient) }
}

extension Optional where Wrapped == [IntentFile] {
    /// The files as a message carries them.
    var drafted: [DraftAttachment] {
        (self ?? []).map { file in
            DraftAttachment(
                filename: file.filename, mimeType: file.type?.preferredMIMEType ?? "application/octet-stream",
                data: file.data)
        }
    }
}
