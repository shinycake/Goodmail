import Dispatch
import MailCore
import dnssd

/// Looks up DNS TXT records, the seam that lets tests answer BIMI lookups.
public protocol TXTResolving: Sendable {
    /// The text of each TXT record at `name`; empty when there are none or the lookup fails or times out.
    func txtRecords(named name: String) async -> [String]
}

/// TXT lookups through the system resolver (DNS-SD), so they go wherever the device's other DNS goes and no
/// third-party resolver learns who writes to the reader.
public struct SystemTXTResolver: TXTResolving {
    /// A lookup gives up after this long, well inside the notification extension's budget.
    private let timeout: DispatchTimeInterval

    public init(timeout: DispatchTimeInterval = .seconds(3)) {
        self.timeout = timeout
    }

    public func txtRecords(named name: String) async -> [String] {
        let query = TXTQuery(name: name, timeout: timeout)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { query.start($0) }
        } onCancel: {
            query.cancel()
        }
    }
}

/// One DNS-SD TXT query.
///
/// `@unchecked Sendable` because DNS-SD's `DNSServiceRef` isn't `Sendable`. Safe: `state` is only read and written on
/// `queue`, a serial queue. DNS-SD delivers its answers there and requires the query to be deallocated there, and
/// `start`, `cancel` and the timeout hop onto it before touching anything.
private final class TXTQuery: @unchecked Sendable {
    private enum State {
        case notStarted
        /// The query is out; `records` are the answers so far.
        case running(DNSServiceRef, CheckedContinuation<[String], Never>, records: [String])
        /// Cancelled before it started, so starting answers at once.
        case cancelled
        case finished
    }

    private let name: String
    private let timeout: DispatchTimeInterval
    private let queue = DispatchQueue(label: "com.idanbirman.goodmail.txt-query")
    /// Only on `queue`.
    private var state = State.notStarted

    init(name: String, timeout: DispatchTimeInterval) {
        self.name = name
        self.timeout = timeout
    }

    func start(_ continuation: CheckedContinuation<[String], Never>) {
        queue.async { [self] in
            guard case .notStarted = state else {
                state = .finished
                return continuation.resume(returning: [])
            }
            var reference: DNSServiceRef?
            let flags = DNSServiceFlags(kDNSServiceFlagsReturnIntermediates | kDNSServiceFlagsTimeout)
            // Unretained: `finish` deallocates the query, which stops callbacks, before it resumes the caller,
            // who holds `self` until then.
            let context = Unmanaged.passUnretained(self).toOpaque()
            let error = DNSServiceQueryRecord(
                &reference, flags, 0, name, UInt16(kDNSServiceType_TXT), UInt16(kDNSServiceClass_IN),
                Self.reply, context)
            guard error == kDNSServiceErr_NoError, let reference else {
                state = .finished
                return continuation.resume(returning: [])
            }
            DNSServiceSetDispatchQueue(reference, queue)
            state = .running(reference, continuation, records: [])
            queue.asyncAfter(deadline: .now() + timeout) { [self] in finish() }
        }
    }

    func cancel() {
        queue.async { [self] in
            if case .notStarted = state {
                state = .cancelled
            } else {
                finish()
            }
        }
    }

    /// DNS-SD's callback, on `queue`.
    private static let reply: DNSServiceQueryRecordReply = {
        _, flags, _, error, _, type, _, length, data, _, context in
        guard let context else { return }
        let query = Unmanaged<TXTQuery>.fromOpaque(context).takeUnretainedValue()
        let record: String? =
            error == kDNSServiceErr_NoError && type == UInt16(kDNSServiceType_TXT) && data != nil
            ? BIMIRecord.text(ofTXTRecordData: Array(UnsafeRawBufferPointer(start: data, count: Int(length))))
            : nil
        query.receive(record, more: flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) != 0, error: error)
    }

    private func receive(_ record: String?, more: Bool, error: DNSServiceErrorType) {
        if let record, case .running(let reference, let continuation, var records) = state {
            records.append(record)
            state = .running(reference, continuation, records: records)
        }
        // A TXT answer, a "no such record", or the resolver's own timeout ends the query; an intermediate answer
        // such as a CNAME doesn't.
        let ended = record != nil || error == kDNSServiceErr_NoSuchRecord || error == kDNSServiceErr_Timeout
        if ended, !more { finish() }
    }

    /// Answers the caller with the records so far, once.
    private func finish() {
        guard case .running(let reference, let continuation, let records) = state else { return }
        state = .finished
        DNSServiceRefDeallocate(reference)
        continuation.resume(returning: records)
    }
}
