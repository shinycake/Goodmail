import Foundation
import MailCore
import MailStore
import MailUI
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
    /// Offers the Apple Watch choice in Settings while a paired watch has the app.
    private weak var model: AppModel?
    /// The latest telling the watch that the owner flipped "Mail Without iPhone"; each waits for the one before.
    private var tellingWatch: Task<Void, Never>?

    init(model: AppModel) {
        host = WristMailHost(
            database: model.database.blocking, commands: model.commands, answers: model.answers,
            independence: { WristIndependence(mailWithoutIPhone: WatchChoices.mailWithoutIPhone) })
        outboxes = model.outboxes
        pairWatch = { [weak model] token in await model?.pairWatch(token) }
        self.model = model
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
        let offerChoices: @Sendable (Bool) async -> Void = { [weak self] hasWatchApp in
            await self?.offerChoices(hasWatchApp, server: server)
        }
        following = Task { @concurrent [host, channel, pairWatch] in
            await channel.activate()
            await withDiscardingTaskGroup { group in
                group.addTask {
                    await Self.follow(
                        channel, into: server, answer: answer, pairWatch: pairWatch, offerChoices: offerChoices)
                }
                group.addTask { await Self.follow(host, into: server) }
            }
        }
    }

    /// Runs the watch's commands, answers its requests for conversations, and gives a watch that was just paired, or
    /// whose app was just installed, what couldn't be sent before. A conversation can take a fetch, so each is
    /// answered beside the commands; the commands run one at a time, in order, in their own task, since a reply sends
    /// mail and would otherwise hold up the requests behind it until the watch stops waiting.
    @concurrent private static func follow(
        _ channel: WristChannel, into server: WristServer,
        answer: @escaping @Sendable (ThreadSummary.ID) async -> WristThreadReply?,
        pairWatch: @escaping @Sendable (String?) async -> Void,
        offerChoices: @escaping @Sendable (Bool) async -> Void
    ) async {
        let (commands, commandsIn) = AsyncStream.makeStream(of: Data.self)
        await withDiscardingTaskGroup { group in
            group.addTask { await run(commands, into: server) }
            for await event in channel.events {
                switch event {
                case .threadRequest(let data):
                    guard let id = try? JSONDecoder().decode(ThreadSummary.ID.self, from: data) else { continue }
                    group.addTask {
                        if let reply = await answer(id) { await channel.answer(reply) }
                    }
                case .watchPushToken(let token):
                    await pairWatch(token)
                case .ready:
                    await channel.sendUnsent()
                    await offerChoices(channel.hasWatchApp)
                case .command(let data):
                    commandsIn.yield(data)
                case .received, .thread:
                    break
                }
            }
            commandsIn.finish()
        }
    }

    /// Runs each command the watch sent, in the order they arrived.
    @concurrent private static func run(_ commands: AsyncStream<Data>, into server: WristServer) async {
        for await data in commands {
            do {
                try await server.received(JSONDecoder().decode(WristCommand.self, from: data))
            } catch {
                log.error("Couldn't make a change from the watch: \(error, privacy: .private)")
            }
        }
    }

    /// Shows the Apple Watch section in Settings while a paired watch has the app, and tells the watch when the owner
    /// flips its switch.
    private func offerChoices(_ hasWatchApp: Bool, server: WristServer) {
        guard let model else { return }
        guard hasWatchApp else {
            model.watchChoices = nil
            return
        }
        guard model.watchChoices == nil else { return }
        model.watchChoices = WatchChoices { [weak self] in self?.tellWatch(server) }
    }

    private func tellWatch(_ server: WristServer) {
        let independence = WristIndependence(mailWithoutIPhone: WatchChoices.mailWithoutIPhone)
        tellingWatch = Task { [previous = tellingWatch] in
            await previous?.value
            await server.independenceChanged(to: independence, at: .now)
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
            log.error("Couldn't load a conversation for the watch: \(error, privacy: .private)")
            return nil
        }
    }

    @concurrent private static func follow(_ host: WristMailHost, into server: WristServer) async {
        do {
            for try await snapshot in host.snapshots() {
                await server.inboxChanged(snapshot)
            }
        } catch {
            log.error("Stopped sending the Inbox to the watch: \(error, privacy: .private)")
        }
    }

    private nonisolated static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "wrist")
}
