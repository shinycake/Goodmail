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
    private let channel = WristChannel()
    /// Follows the Inbox and the session for the app's lifetime.
    private var following: Task<Void, Never>?

    init(model: AppModel) {
        database = model.database
        commands = model.commands
        outboxes = model.outboxes
    }

    func start() {
        let applied = (UserDefaults.standard.stringArray(forKey: Self.appliedKey) ?? []).compactMap(UUID.init)
        let server = WristServer(
            applied: applied,
            execute: { [commands, outboxes] command in
                try await BackgroundDatabaseWork.shared.run("A change from the watch") {
                    try await Self.execute(command, commands: commands)
                    for account in Set(command.threads.map(\.accountID)) { await outboxes.flush(account) }
                }
            },
            send: { [channel] snapshot in await channel.send(snapshot) },
            remember: { applied in
                UserDefaults.standard.set(applied.map(\.uuidString), forKey: Self.appliedKey)
            })
        following = Task { @concurrent [database, channel] in
            await channel.activate()
            await withDiscardingTaskGroup { group in
                group.addTask { await Self.follow(channel, into: server) }
                group.addTask { await Self.follow(database, into: server) }
            }
        }
    }

    @concurrent private static func execute(_ command: WristCommand, commands: MailCommands) async throws {
        switch command.kind.threadAction {
        case .some(let action): _ = try await commands.perform(action, on: command.threads)
        case .none:
            if case .pin(let pinned) = command.kind { _ = try await commands.pin(command.threads, pinned) }
        }
    }

    /// Runs the watch's commands, and gives a watch that was just paired, or whose app was just installed, what
    /// couldn't be sent before.
    @concurrent private static func follow(_ channel: WristChannel, into server: WristServer) async {
        for await event in channel.events {
            switch event {
            case .ready:
                await channel.sendUnsent()
            case .command(let data):
                do {
                    try await server.received(JSONDecoder().decode(WristCommand.self, from: data))
                } catch {
                    log.error("Couldn't make a change from the watch: \(error, privacy: .public)")
                }
            case .received:
                break
            }
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
