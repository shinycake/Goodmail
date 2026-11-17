import Foundation
import MailCore
import MailWrist
import MailWristHost
import OSLog

/// The iPhone's side of the Apple Watch app (ADR-022): it keeps the watch's copy of the Inbox current, and makes the
/// changes the reader makes on the watch.
final class WristHost {
    private nonisolated static let appliedKey = "WristAppliedCommands"

    private let host: WristMailHost
    private let outboxes: Outboxes
    /// Registers the watch's push token with the relay (ADR-023).
    private let pairWatch: @Sendable (String?) async -> Void
    private let channel = WristChannel()
    /// Follows the Inbox and the session for the app's lifetime.
    private var following: Task<Void, Never>?

    init(model: AppModel) {
        host = WristMailHost(database: model.database, commands: model.commands, answers: model.answers)
        outboxes = model.outboxes
        pairWatch = { [weak model] token in await model?.pairWatch(token) }
    }

    func start() {
        let applied = (UserDefaults.standard.stringArray(forKey: Self.appliedKey) ?? []).compactMap(UUID.init)
        let server = WristServer(
            applied: applied,
            execute: { [host, outboxes] command in
                try await BackgroundDatabaseWork.shared.run("A change from the watch") {
                    try await host.execute(command)
                    for account in Set(command.threads.map(\.accountID)) { await outboxes.flush(account) }
                }
            },
            send: { [channel] snapshot in await channel.send(snapshot) },
            remember: { applied in
                UserDefaults.standard.set(applied.map(\.uuidString), forKey: Self.appliedKey)
            })
        let answer: @Sendable (ThreadSummary.ID) async -> WristThreadReply? = { [host] id in
            await Self.conversation(id, from: host)
        }
        following = Task { @concurrent [host, channel, pairWatch] in
            await channel.activate()
            await withDiscardingTaskGroup { group in
                group.addTask { await Self.follow(channel, into: server, answer: answer, pairWatch: pairWatch) }
                group.addTask { await Self.follow(host, into: server) }
            }
        }
    }

    /// Runs the watch's commands, answers its requests for conversations, and gives a watch that was just paired, or
    /// whose app was just installed, what couldn't be sent before. A conversation can take a fetch, so each is
    /// answered beside the commands rather than ahead of them.
    @concurrent private static func follow(
        _ channel: WristChannel, into server: WristServer,
        answer: @escaping @Sendable (ThreadSummary.ID) async -> WristThreadReply?,
        pairWatch: @escaping @Sendable (String?) async -> Void
    ) async {
        await withDiscardingTaskGroup { group in
            for await event in channel.events {
                if case .threadRequest(let data) = event {
                    guard let id = try? JSONDecoder().decode(ThreadSummary.ID.self, from: data) else { continue }
                    group.addTask {
                        if let reply = await answer(id) { await channel.answer(reply) }
                    }
                } else if case .watchPushToken(let token) = event {
                    await pairWatch(token)
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
        case .received, .threadRequest, .thread, .watchPushToken:
            break
        }
    }

    /// The conversation the watch asked for, or `nil` when it can't be had now, so the watch says the iPhone didn't
    /// answer.
    private static func conversation(_ id: ThreadSummary.ID, from host: WristMailHost) async -> WristThreadReply? {
        do {
            return try await BackgroundDatabaseWork.shared.run("A conversation for the watch") {
                try await host.conversation(id)
            }
        } catch {
            log.error("Couldn't load a conversation for the watch: \(error, privacy: .public)")
            return nil
        }
    }

    @concurrent private static func follow(_ host: WristMailHost, into server: WristServer) async {
        do {
            for try await snapshot in host.snapshots() {
                await server.inboxChanged(snapshot)
            }
        } catch {
            log.error("Stopped sending the Inbox to the watch: \(error, privacy: .public)")
        }
    }

    private nonisolated static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "wrist")
}
