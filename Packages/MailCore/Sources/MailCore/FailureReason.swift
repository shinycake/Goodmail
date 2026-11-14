import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Why something failed, in terms the reader can act on, read from the error a network or sign-in call threw. The
/// errors themselves only make sense to a developer: "Network.NWError error 57" is a socket the server dropped.
public enum FailureReason: Equatable, Sendable {
    /// The device has no internet connection.
    case offline
    /// A connection that was open broke, as when the server drops it.
    case connectionLost
    /// The server didn't answer in time.
    case timedOut
    /// The server couldn't be found or refused to connect.
    case serverUnreachable
    /// The connection couldn't be made secure, as when the server's certificate isn't valid.
    case insecure
    /// The service didn't finish the sign-in, or turned it down.
    case signInFailed
    /// None of the above.
    case unknown

    public init(_ error: any Error) {
        self = Self.reason(for: error)
        if self == .unknown, let underlying = (error as NSError).userInfo[NSUnderlyingErrorKey] as? any Error {
            self = Self.reason(for: underlying)
        }
    }

    private static func reason(for error: any Error) -> FailureReason {
        switch error {
        case let error as URLError: reason(for: error.code)
        case let error as OAuthClient.Failure:
            switch error {
            case .missingCode, .stateMismatch, .tokenEndpoint: .signInFailed
            }
        case OAuthSession.Failure.signedOut: .signInFailed
        default: reason(for: error as NSError)
        }
    }

    private static func reason(for code: URLError.Code) -> FailureReason {
        switch code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: .offline
        case .networkConnectionLost: .connectionLost
        case .timedOut: .timedOut
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed: .serverUnreachable
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
            .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
            .insecure
        default: .unknown
        }
    }

    /// The Network framework's `NWError`, as the IMAP and SMTP stream tasks throw it, and the POSIX errors under it.
    private static func reason(for error: NSError) -> FailureReason {
        switch error.domain {
        case "Network.NWError":
            // NWError's code is a POSIX code, a DNSServiceErrorType or a TLS OSStatus, each in its own range.
            switch error.code {
            case 1...: reason(posix: error.code)
            case -65_999 ... -65_537: .serverUnreachable
            case -9_899 ... -9_800: .insecure
            default: .unknown
            }
        case NSPOSIXErrorDomain: reason(posix: error.code)
        default: .unknown
        }
    }

    /// Darwin's numbers, which the errors carry whatever platform reads them.
    private static func reason(posix code: Int) -> FailureReason {
        switch code {
        case 50, 51: .offline  // ENETDOWN, ENETUNREACH
        case 32, 52, 53, 54, 57: .connectionLost  // EPIPE, ENETRESET, ECONNABORTED, ECONNRESET, ENOTCONN
        case 60: .timedOut  // ETIMEDOUT
        case 61, 64, 65: .serverUnreachable  // ECONNREFUSED, EHOSTDOWN, EHOSTUNREACH
        default: .unknown
        }
    }
}
