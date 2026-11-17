import MailCore
import SwiftUI

extension FailureReason {
    /// Why the watch can't check its mail, in a few words.
    var text: Text {
        switch self {
        case .offline:
            Text(
                "The watch is offline.", tableName: "Wrist", bundle: .module,
                comment: "Why the watch can't check mail: no internet connection")
        case .connectionLost, .timedOut, .serverUnreachable:
            Text(
                "The mail service didn’t answer.", tableName: "Wrist", bundle: .module,
                comment: "Why the watch can't check mail: the server couldn't be reached or timed out")
        case .insecure:
            Text(
                "The connection isn’t secure.", tableName: "Wrist", bundle: .module,
                comment: "Why the watch can't check mail: the server's certificate isn't valid")
        case .signInFailed:
            Text(
                "Sign in again on your iPhone.", tableName: "Wrist", bundle: .module,
                comment: "Why the watch can't check mail: the service turned the sign-in down")
        case .unknown:
            Text(
                "Something went wrong.", tableName: "Wrist", bundle: .module,
                comment: "Why the watch can't check mail: an error with no better description")
        }
    }
}
