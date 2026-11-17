import Foundation
import MailCore
import MailStore
import MailWrist
import MailWristHost
import OSLog

/// The Gmail and Outlook accounts the watch reads itself (ADR-023): its own database and host, following the accounts
/// and the switch each iPhone snapshot carries, feeding the host's Inbox to the Inbox screen and running the commands
/// stamped for the watch, each once.
final class OwnMail {
    nonisolated static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "own-mail")

    /// The commands stamped for the watch, in the order they were made.
    private let commands: AsyncStream<WristCommand>
    private let commandsIn: AsyncStream<WristCommand>.Continuation
    /// Asks for a check of the mail; asks made while one runs make one more after it.
    private let checks: AsyncStream<Void>
    private let checksIn: AsyncStream<Void>.Continuation

    init() {
        (commands, commandsIn) = AsyncStream.makeStream(of: WristCommand.self)
        (checks, checksIn) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
    }

    /// Runs `command` at the account's service. Returns at once, so it never holds up the link to the iPhone.
    func run(_ command: WristCommand) {
        commandsIn.yield(command)
    }

    /// Checks the mail of every account the watch reads itself, as when the app comes to the front.
    func checkMail() {
        checksIn.yield()
    }

    /// Runs for the app's lifetime: opens the watch's own mail, then follows the iPhone's accounts, feeds the Inbox,
    /// runs commands and checks the mail when asked. Without its database the watch shows what the iPhone sends.
    func run(inbox: WristInboxModel, threads: WristThreads) async {
        guard let host = await Self.openHost() else { return }
        threads.own = { id in try await host.conversation(id) }
        let server = WristServer(
            applied: AppliedCommands.load(), execute: { try await host.execute($0) },
            send: { snapshot in await Self.show(snapshot, sources: try? await host.sources(), in: inbox, threads) },
            remember: AppliedCommands.save)
        async let following: Void = follow(inbox, threads: threads, host: host)
        async let feeding: Void = Self.feed(from: host, to: server)
        async let running: Void = Self.run(commands, on: server)
        async let checking: Void = check(host, inbox: inbox, threads: threads)
        async let footing: Void = Self.showFreshness(of: host, in: inbox)
        _ = await (following, feeding, running, checking, footing)
    }

    /// Keeps the list footer on how fresh the watch's own mail is.
    private static func showFreshness(of host: WristOwnHost, in inbox: WristInboxModel) async {
        for await freshness in host.freshnessUpdates { inbox.freshness = freshness }
    }

    /// Opens the database in the app's own container, which only the watch app reads, and the host over it.
    @concurrent private static func openHost() async -> WristOwnHost? {
        let folder = URL.applicationSupportDirectory.appending(path: "OwnMail", directoryHint: .isDirectory)
        do {
            // MailDatabase protects its folder until the first unlock, so background checks can still open it.
            let database = try MailDatabase(url: folder.appending(path: "mail.sqlite"))
            let signIns = WristSignIns(device: Keychain(), shared: Keychain.iCloud)
            #if DEBUG
                seedSignInsIfRequested(into: signIns)
            #endif
            let providers = WristProviders(signIns: signIns, index: database)
            return WristOwnHost(
                database: database, signIns: signIns, provider: { try providers.provider(for: $0) },
                uploads: folder.appending(path: "Uploads", directoryHint: .isDirectory))
        } catch {
            log.error("Couldn't open the watch's own mail: \(error, privacy: .public)")
            return nil
        }
    }

    /// Takes the accounts and the switch from each iPhone snapshot that changes them, and checks the mail after.
    private func follow(_ inbox: WristInboxModel, threads: WristThreads, host: WristOwnHost) async {
        var followed: Following?
        for await following in Observations({ Following(inbox.mailbox) }) {
            guard let following, following != followed else { continue }
            followed = following
            do {
                try await host.follow(following.accounts, independence: following.independence)
            } catch {
                Self.log.error("Couldn't follow the iPhone's accounts: \(error, privacy: .public)")
            }
            Self.resend(in: inbox, threads, sources: try? await host.sources())
            checkMail()
        }
    }

    /// Checks the mail for each ask, and shows each account's new source after.
    private func check(_ host: WristOwnHost, inbox: WristInboxModel, threads: WristThreads) async {
        for await _ in checks {
            do {
                try await host.sync()
            } catch {
                Self.log.error("Couldn't check the watch's own mail: \(error, privacy: .public)")
            }
            // A sync can change a source without changing the Inbox, as when a sign-in is turned down.
            Self.resend(in: inbox, threads, sources: try? await host.sources())
        }
    }

    @concurrent private static func feed(from host: WristOwnHost, to server: WristServer) async {
        do {
            for try await snapshot in host.snapshots() { await server.inboxChanged(snapshot) }
        } catch {
            log.error("Stopped reading the watch's own Inbox: \(error, privacy: .public)")
        }
    }

    @concurrent private static func run(_ commands: AsyncStream<WristCommand>, on server: WristServer) async {
        for await command in commands {
            do {
                try await server.received(command)
            } catch {
                log.error("Couldn't run a command on the watch: \(error, privacy: .public)")
            }
        }
    }

    /// Shows the watch's own `snapshot` with each account's `sources`, or the last sources when they can't be read.
    private static func show(
        _ snapshot: WristSnapshot, sources: [AccountID: WristAccountSource]?, in inbox: WristInboxModel,
        _ threads: WristThreads
    ) {
        let sources = sources ?? inbox.mailbox.sources
        inbox.receiveOwn(snapshot, sources: sources)
        threads.direct = Set(sources.filter { $0.value == .direct }.keys)
    }

    /// Shows the last own snapshot again with new `sources`.
    private static func resend(
        in inbox: WristInboxModel, _ threads: WristThreads, sources: [AccountID: WristAccountSource]?
    ) {
        guard let own = inbox.mailbox.own else { return }
        show(own, sources: sources, in: inbox, threads)
    }
}

/// What the watch's own mail takes from the iPhone: its accounts, without their counts, and the owner's switch.
private nonisolated struct Following: Equatable, Sendable {
    let accounts: [WristAccount]
    let independence: WristIndependence

    /// `nil` until the iPhone has sent a snapshot, so a watch that hasn't heard from it yet keeps its accounts.
    init?(_ mailbox: WristMailbox) {
        guard let phone = mailbox.snapshot else { return nil }
        accounts = phone.accounts.map { account in
            var account = account
            account.unread = 0
            return account
        }
        #if DEBUG
            if OwnMail.forcesIndependence {
                independence = .on
                return
            }
        #endif
        independence = mailbox.extras?.independence ?? .default
    }
}

/// The commands the watch ran itself, kept so a command made again after a relaunch still runs once.
private nonisolated enum AppliedCommands {
    private static let key = "WristOwnAppliedCommands"

    static func load() -> [UUID] {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).compactMap(UUID.init(uuidString:))
    }

    static func save(_ applied: [UUID]) {
        UserDefaults.standard.set(applied.map(\.uuidString), forKey: key)
    }
}
