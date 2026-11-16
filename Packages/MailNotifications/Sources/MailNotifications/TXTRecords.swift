public import Dispatch
import MailCore
public import dnssd

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
///
/// Its `unsafe` calls are DNS-SD's C API, which takes the query as a raw pointer to it and hands back a
/// `DNSServiceRef`. Safe: the reference lives in `state` from the moment it is created until `finish` deallocates
/// it, once, and the callbacks it makes end with it.
private final class TXTQuery: @unchecked Sendable {
    /// `@safe`: the `DNSServiceRef` in `running` is only made, used and deallocated by `TXTQuery`, as above.
    @safe private enum State {
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
            let context = unsafe Unmanaged.passUnretained(self).toOpaque()
            let error = unsafe DNSServiceQueryRecord(
                &reference, flags, 0, name, UInt16(kDNSServiceType_TXT), UInt16(kDNSServiceClass_IN),
                Self.reply, context)
            guard error == kDNSServiceErr_NoError, let reference = unsafe reference else {
                state = .finished
                return continuation.resume(returning: [])
            }
            unsafe DNSServiceSetDispatchQueue(reference, queue)
            state = unsafe .running(reference, continuation, records: [])
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
        guard let context = unsafe context else { return }
        let query = unsafe Unmanaged<TXTQuery>.fromOpaque(context).takeUnretainedValue()
        // DNS-SD's buffer lasts as long as the callback, so its bytes are copied out here.
        let record: String? =
            error == kDNSServiceErr_NoError && type == UInt16(kDNSServiceType_TXT) && (unsafe data != nil)
            ? BIMIRecord.text(ofTXTRecordData: unsafe Array(UnsafeRawBufferPointer(start: data, count: Int(length))))
            : nil
        query.receive(record, more: flags & DNSServiceFlags(kDNSServiceFlagsMoreComing) != 0, error: error)
    }

    private func receive(_ record: String?, more: Bool, error: DNSServiceErrorType) {
        if let record, case .running(let reference, let continuation, var records) = state {
            records.append(record)
            state = unsafe .running(reference, continuation, records: records)
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
        unsafe DNSServiceRefDeallocate(reference)
        continuation.resume(returning: records)
    }
}
