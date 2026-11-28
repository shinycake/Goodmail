#if canImport(os)
    import os
#endif

/// Where the mail modules record a failure they deal with by carrying on: a write that didn't land, a read that fell
/// back, a copy that wasn't filed. It goes to the system log on Apple platforms and nowhere on Linux, or to a sink a
/// test gives.
///
/// What it records is a fixed sentence, the error's type and the error's description. Only the sentence and the type
/// are public. The description is private, since it can carry what a server said back, such as a folder name, an
/// address or a Message-ID, so the system log redacts it outside a debugging session.
public struct MailLog: Sendable {
    public enum Level: Sendable {
        /// Something failed, and what depended on it was skipped or put off.
        case error
        /// Something failed that must never fail, such as a sent message that couldn't leave the queue.
        case fault
    }

    /// One record, as a sink receives it.
    public struct Entry: Sendable, Equatable {
        public var category: String
        public var level: Level
        public var message: String
        /// The error's type, in full, as `ProviderError` or `IMAPError`.
        public var errorType: String
        /// What the error says about itself. Private in the system log.
        public var error: String
    }

    private enum Destination: Sendable {
        #if canImport(os)
            case system(Logger)
        #endif
        case sink(@Sendable (Entry) -> Void)
    }

    public let category: String
    private let destination: Destination

    /// Records to the system log under `category`, where there is one.
    public init(category: String) {
        self.category = category
        #if canImport(os)
            destination = .system(Logger(subsystem: "com.idanbirman.goodmail", category: category))
        #else
            destination = .sink { _ in }
        #endif
    }

    /// Hands every record to `sink` instead, as a test does to see what was recorded.
    public init(category: String, sink: @escaping @Sendable (Entry) -> Void) {
        self.category = category
        destination = .sink(sink)
    }

    public func error(_ message: StaticString, _ error: any Error) {
        record(.error, message, error)
    }

    public func fault(_ message: StaticString, _ error: any Error) {
        record(.fault, message, error)
    }

    private func record(_ level: Level, _ message: StaticString, _ error: any Error) {
        let text = message.description
        let type = String(reflecting: Swift.type(of: error))
        let description = String(describing: error)
        switch destination {
        #if canImport(os)
            case .system(let logger):
                // `message` is a literal of ours, and `type` a name in our code or the SDK's: both as public as the
                // log's own format strings.
                switch level {
                case .error:
                    logger.error(
                        "\(text, privacy: .public) [\(type, privacy: .public)] \(description, privacy: .private)")
                case .fault:
                    logger.fault(
                        "\(text, privacy: .public) [\(type, privacy: .public)] \(description, privacy: .private)")
                }
        #endif
        case .sink(let sink):
            sink(Entry(category: category, level: level, message: text, errorType: type, error: description))
        }
    }
}
