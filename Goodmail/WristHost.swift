import Foundation
import MailCore
import MailStore
import MailWrist
import OSLog

/// The iPhone's side of the Apple Watch app (ADR-022): it keeps the watch's copy of the Inbox current, and makes the
/// changes the reader makes on the watch.
final class WristHost {
    private nonisolated static let appliedKey = "WristAppliedCommands"

    private let database: MailDatabase
    private let commands: MailCommands
    private let outboxes: Outboxes
    private let model: AppModel
    private let channel = WristChannel()
    /// Follows the Inbox and the session for the app's lifetime.
    private var following: Task<Void, Never>?

    init(model: AppModel) {
        database = model.database
        commands = model.commands
        outboxes = model.outboxes
        self.model = model
    }

    func start() {
        let applied = (UserDefaults.standard.stringArray(forKey: Self.appliedKey) ?? []).compactMap(UUID.init)
        let server = WristServer(
            applied: applied,
            execute: { [commands, outboxes, model] command in
                try await BackgroundDatabaseWork.shared.run("A change from the watch") {
                    try await Self.execute(command, commands: commands, model: model)
                    for account in Set(command.threads.map(\.accountID)) { await outboxes.flush(account) }
                }
            },
            send: { [channel] snapshot in await channel.send(snapshot) },
            remember: { applied in
                UserDefaults.standard.set(applied.map(\.uuidString), forKey: Self.appliedKey)
            })
        let answer: @Sendable (ThreadSummary.ID) async -> WristThreadReply? = { [model] id in
            await Self.reply(to: id, model: model)
        }
        following = Task { @concurrent [database, channel] in
            await channel.activate()
            await withDiscardingTaskGroup { group in
                group.addTask { await Self.follow(channel, into: server, answer: answer) }
                group.addTask { await Self.follow(database, into: server) }
            }
        }
    }

    @concurrent private static func execute(
        _ command: WristCommand, commands: MailCommands, model: AppModel
    ) async throws {
        switch command.kind {
        case .reply(let text):
            for thread in command.threads { try await model.reply(to: thread, with: text) }
        case .pin(let pinned):
            _ = try await commands.pin(command.threads, pinned)
        case .archive, .moveToInbox, .trash, .untrash, .markRead:
            if let action = command.kind.threadAction { _ = try await commands.perform(action, on: command.threads) }
        }
    }

    /// Runs the watch's commands, answers its requests for conversations, and gives a watch that was just paired, or
    /// whose app was just installed, what couldn't be sent before. A conversation can take a fetch, so each is
    /// answered beside the commands rather than ahead of them.
    @concurrent private static func follow(
        _ channel: WristChannel, into server: WristServer,
        answer: @escaping @Sendable (ThreadSummary.ID) async -> WristThreadReply?
    ) async {
        await withDiscardingTaskGroup { group in
            for await event in channel.events {
                if case .threadRequest(let data) = event {
                    guard let id = try? JSONDecoder().decode(ThreadSummary.ID.self, from: data) else { continue }
                    group.addTask {
                        if let reply = await answer(id) { await channel.answer(reply) }
                    }
                } else {
                    await handle(event, from: channel, into: server)
                }
            }
        }
    }

    @concurrent private static func handle(
        _ event: WristSessionEvent, from channel: WristChannel, into server: WristServer
    ) async {
        switch event {
        case .ready:
            await channel.sendUnsent()
        case .command(let data):
            do {
                try await server.received(JSONDecoder().decode(WristCommand.self, from: data))
            } catch {
                log.error("Couldn't make a change from the watch: \(error, privacy: .public)")
            }
        case .received, .threadRequest, .thread:
            break
        }
    }

    /// The conversation the watch asked for, as the reader's chat view shows it: the cached messages when they're
    /// current, otherwise fetched first. `nil` when it can't be had now, so the watch says the iPhone didn't answer.
    private static func reply(to id: ThreadSummary.ID, model: AppModel) async -> WristThreadReply? {
        guard let account = model.accounts.first(where: { $0.id == id.accountID }) else { return .gone(id) }
        do {
            let messages = try await BackgroundDatabaseWork.shared.run("A conversation for the watch") {
                try await model.messagesToAnswer(in: id)
            }
            guard let first = messages.first else { return .gone(id) }
            let transcript = ChatTranscript(messages: messages, accountEmail: account.email, aliases: account.aliases)
            return .thread(WristThread(id: id, subject: first.subject, transcript: transcript))
        } catch {
            log.error("Couldn't load a conversation for the watch: \(error, privacy: .public)")
            return nil
        }
    }

    @concurrent private static func follow(_ database: MailDatabase, into server: WristServer) async {
        do {
            for try await glance in database.inboxGlance(limit: WristSnapshot.rowLimit) {
                await server.inboxChanged(
                    WristSnapshot(
                        accounts: glance.accounts, threads: glance.threads, pinned: glance.pinned,
                        unread: glance.unread, madeAt: .now))
            }
        } catch {
            log.error("Stopped sending the Inbox to the watch: \(error, privacy: .public)")
        }
    }

    private nonisolated static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "wrist")
}
