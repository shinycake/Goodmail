public import AppIntents
public import Foundation
import MailCore
import UniformTypeIdentifiers

/// Gets the messages of conversations, downloading any the device doesn't hold yet, so a conversation found or open
/// can be read, answered or have its attachments saved.
public struct GetMessagesIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Get Messages in Conversations", table: "ShortcutFlow")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Gets the messages of conversations, oldest first, and downloads any this device doesn't have yet. Turn on Latest Only to get just the newest message of each.",
            table: "ShortcutFlow"))

    @Parameter(title: LocalizedStringResource("Conversations", table: "ShortcutFlow"))
    public var threads: [ThreadEntity]

    @Parameter(title: LocalizedStringResource("Latest Only", table: "ShortcutFlow"), default: false)
    public var latestOnly: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        When(\.$latestOnly, .equalTo, true) {
            Summary("Get the latest message in \(\.$threads)", table: "ShortcutFlow") { \.$latestOnly }
        } otherwise: {
            Summary("Get the messages in \(\.$threads)", table: "ShortcutFlow") { \.$latestOnly }
        }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[MessageEntity]> {
        let messages = try await Catalog(host: host).messages(ofThreads: threads.map(\.id), latestOnly: latestOnly)
        return .result(value: messages)
    }
}

/// Downloads the files attached to messages, as files Shortcuts can save, share, preview or attach elsewhere.
public struct GetAttachmentsIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Get Attachments", table: "ShortcutFlow")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Downloads the files attached to messages, to save to Files, share or send on. Pictures shown inside a message, such as logos, are left out unless you include them.",
            table: "ShortcutFlow"))

    @Parameter(title: LocalizedStringResource("Messages", table: "ShortcutFlow"))
    public var messages: [MessageEntity]

    @Parameter(title: LocalizedStringResource("Include Inline Pictures", table: "ShortcutFlow"), default: false)
    public var includesInline: Bool

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Get the attachments of \(\.$messages)", table: "ShortcutFlow") { \.$includesInline }
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        let files = try await Catalog(host: host).attachments(
            ofMessages: messages.map(\.id), includingInline: includesInline)
        return .result(value: files)
    }
}

/// Gets messages as `.eml` files: the original email, attachments and all, which any mail app opens.
public struct GetEmailFilesIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Get Email Files", table: "ShortcutFlow")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Gets each message as an .eml file, the original email with its attachments, which Mail, Outlook and other apps open. Save it, share it or attach it to another email.",
            table: "ShortcutFlow"))

    @Parameter(title: LocalizedStringResource("Messages", table: "ShortcutFlow"))
    public var messages: [MessageEntity]

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public static var parameterSummary: some ParameterSummary {
        Summary("Get \(\.$messages) as email files", table: "ShortcutFlow")
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        .result(value: try await Catalog(host: host).emailFiles(ofMessages: messages.map(\.id)))
    }
}

/// Gets the conversation open in Goodmail, so a shortcut run from the Action button or Back Tap acts on what's
/// being read.
public struct GetOpenConversationIntent: AppIntent {
    public static let title: LocalizedStringResource = LocalizedStringResource(
        "Get Open Conversation", table: "ShortcutFlow")
    public static let description = IntentDescription(
        LocalizedStringResource(
            "Gets the conversation you're reading in Goodmail, so a shortcut you run from the Action button or Back Tap can act on it.",
            table: "ShortcutFlow"))

    @Dependency private var host: any MailIntentsHost

    public init() {}

    public func perform() async throws -> some IntentResult & ReturnsValue<ThreadEntity> {
        guard let id = await host.openThread(), let thread = try Catalog(host: host).threads(ids: [id]).first else {
            throw IntentError.nothingOpen
        }
        return .result(value: thread)
    }
}

extension Catalog {
    /// The messages of the threads, oldest first in each, once the device holds them all; with `latestOnly`, the
    /// newest of each.
    func messages(ofThreads identifiers: [String], latestOnly: Bool) async throws -> [MessageEntity] {
        // An automation's Find can come up empty; doing nothing then is a success, so the shortcut runs on.
        guard !identifiers.isEmpty else { return [] }
        let ids = identifiers.compactMap(EntityID.thread)
        guard !ids.isEmpty else { throw IntentError.gone }
        try await host.loadMessages(of: ids)
        return try threads(ids: ids).flatMap { latestOnly ? Array($0.messages.suffix(1)) : $0.messages }
    }

    /// The files attached to the messages, in order, downloaded one after another so a long list doesn't flood the
    /// server. Inline pictures only with `includingInline`.
    func attachments(ofMessages identifiers: [String], includingInline: Bool) async throws -> [IntentFile] {
        var files: [IntentFile] = []
        for identifier in identifiers {
            guard let content = try facts(ofMessage: identifier).content else { continue }
            for attachment in content.attachments + (includingInline ? content.inlineAttachments : []) {
                try Task.checkCancellation()
                let data = try await host.data(for: attachment, in: content.id)
                files.append(
                    IntentFile(data: data, filename: attachment.filename, type: UTType(mimeType: attachment.mimeType)))
            }
        }
        return files
    }

    /// Each message's raw source as an `.eml` file named for its subject: "Plan.eml", then "Plan 2.eml".
    func emailFiles(ofMessages identifiers: [String]) async throws -> [IntentFile] {
        let fallback = String(localized: LocalizedStringResource("Message", table: "ShortcutFlow"))
        var named: [String: Int] = [:]
        var files: [IntentFile] = []
        for identifier in identifiers {
            let facts = try facts(ofMessage: identifier)
            guard let content = facts.content else { continue }
            try Task.checkCancellation()
            let data = try await host.source(of: content.id)
            let subject = facts.envelope.subject
            named[subject, default: 0] += 1
            let names = ExportFilename.names(
                for: subject, count: named[subject, default: 1], fallback: fallback, extension: "eml")
            files.append(IntentFile(data: data, filename: names.last ?? "\(fallback).eml", type: Self.emailFile))
        }
        return files
    }

    /// What an `.eml` file is.
    static let emailFile = UTType(filenameExtension: "eml") ?? .data
}
