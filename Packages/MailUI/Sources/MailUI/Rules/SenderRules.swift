public import MailCore
import OSLog
public import Observation

/// Apply Rules, Block Sender and VIPs (ADR-038), one for the app, which the menu bar, the keyboard and the context menus
/// of every window reach through their screens. The work runs off the main actor, in the order the reader asked for
/// it, and the service logs what fails: none of it has anything for the reader to fix.
@Observable
public final class SenderRules {
    /// How the work is done, by the app.
    public struct Service {
        /// Runs the rules on the conversations now.
        let applyRules: ([ThreadSummary.ID]) async -> Void
        /// Writes Block Sender's rule for the sender, under the name given.
        let block: (SenderAddress, String) async -> Void
        let setVIP: (SenderAddress, Bool) async -> Void
        /// The VIPs, now and after every change.
        let vips: () -> AsyncThrowingStream<VIPList, any Error>

        public init(
            applyRules: @escaping ([ThreadSummary.ID]) async -> Void,
            block: @escaping (SenderAddress, String) async -> Void,
            setVIP: @escaping (SenderAddress, Bool) async -> Void,
            vips: @escaping () -> AsyncThrowingStream<VIPList, any Error>
        ) {
            self.applyRules = applyRules
            self.block = block
            self.setVIP = setVIP
            self.vips = vips
        }
    }

    /// The VIPs as the store last gave them, for the menus to say Add or Remove.
    public private(set) var vips = VIPList()
    @ObservationIgnored private let service: Service
    @ObservationIgnored private let chain = TaskChain()
    /// Follows the VIPs for the life of the app, from `start()`.
    @ObservationIgnored private var following: Task<Void, Never>?

    public init(service: Service) {
        self.service = service
    }

    isolated deinit {
        following?.cancel()
    }

    /// Starts following the VIPs. Call once.
    public func start() {
        following = Task { [weak self, service] in
            do {
                for try await vips in service.vips() { self?.vips = vips }
            } catch {
                Logger(subsystem: "com.idanbirman.goodmail", category: "rules")
                    .error("The VIPs stopped updating: \(error, privacy: .private)")
            }
        }
    }

    public func applyRules(to threads: [ThreadSummary.ID]) {
        chain.run { [service] in await service.applyRules(threads) }
    }

    /// Blocks `sender`, then runs the rules on `threads`, so the conversation the reader blocked them from goes to
    /// Trash with the rest of their mail to come.
    public func block(_ sender: SenderAddress, then threads: [ThreadSummary.ID]) {
        let name = Self.blockName(sender)
        chain.run { [service] in
            await service.block(sender, name)
            await service.applyRules(threads)
        }
    }

    public func setVIP(_ sender: SenderAddress, _ isVIP: Bool) {
        // The menu says the new state at once; the store's next value confirms it.
        vips.set(sender, isVIP: isVIP)
        chain.run { [service] in await service.setVIP(sender, isVIP) }
    }

    /// Waits for the work asked for so far.
    func settled() async {
        await chain.settled()
    }

    /// The name Block Sender's rule has in Settings.
    static func blockName(_ sender: SenderAddress) -> String {
        String(
            localized: "Block \(sender.address)", table: "SenderRules", bundle: .module,
            comment: "The name of the rule Block Sender writes; the argument is the sender's address")
    }
}
