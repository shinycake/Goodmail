import Foundation
import MailCore

nonisolated extension FailureReason {
    /// What an alert tells the reader about a failed `error`: what went wrong and what to do, never the error's type
    /// and number. An error that explains itself, as a `LocalizedError` does, keeps its own words.
    static func message(for error: any Error) -> String {
        let reason = FailureReason(error)
        if reason == .unknown, let error = error as? any LocalizedError, let description = error.errorDescription {
            return description
        }
        return reason.message
    }

    var message: String {
        switch self {
        case .offline:
            String(
                localized: "You’re offline. Connect to the internet and try again.", table: "Failures",
                bundle: .module, comment: "Failure: the device has no internet connection")
        case .connectionLost:
            String(
                localized: "The connection to the server was lost. Try again.", table: "Failures", bundle: .module,
                comment: "Failure: an open connection to the mail server broke")
        case .timedOut:
            String(
                localized: "The server took too long to answer. Try again in a moment.", table: "Failures",
                bundle: .module, comment: "Failure: the mail server didn't answer in time")
        case .serverUnreachable:
            String(
                localized: "Goodmail couldn’t reach the server. Check your connection and try again.",
                table: "Failures", bundle: .module, comment: "Failure: the mail server couldn't be found or reached")
        case .insecure:
            String(
                localized: "Goodmail couldn’t make a secure connection to the server, so nothing was sent.",
                table: "Failures", bundle: .module, comment: "Failure: TLS to the mail server failed")
        case .signInFailed:
            String(
                localized: "The sign-in didn’t finish. Try signing in again.", table: "Failures", bundle: .module,
                comment: "Failure: the provider didn't complete or refused the sign-in")
        case .unknown:
            String(
                localized: "Something went wrong. Try again.", table: "Failures", bundle: .module,
                comment: "Failure: an error with no better explanation")
        }
    }
}
