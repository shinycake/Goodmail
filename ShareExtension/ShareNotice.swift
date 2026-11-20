import Foundation
import MailCore

/// What the sheet tells the writer before it closes, when a message didn't simply go.
enum ShareNotice {
    /// No account to send from yet.
    case noAccounts
    /// The mail Goodmail keeps couldn't be opened.
    case unavailable
    /// Couldn't reach the service; the app sends or saves it later.
    case waiting(ShareSession.Errand)
    /// The account's sign-in isn't on this device; the app sends or saves it once the writer signs in.
    case signedOut(ShareSession.Errand)
    /// The upload ended without an answer; the app checks whether it went.
    case unconfirmed
    /// The service refused it; it waits in the app to be fixed.
    case refused(ShareSession.Errand)
    /// It couldn't even be put in the app's queue, so the writer is back in the message.
    case notKept
    /// It couldn't be put in the app's queue, and may have gone already.
    case mayHaveGone

    init(_ errand: ShareSession.Errand, leftAs delivery: OutgoingMessage.Delivery) {
        switch delivery {
        case .queued: self = .waiting(errand)
        case .uploading: self = .unconfirmed
        case .failed: self = .refused(errand)
        }
    }

    var title: String {
        switch self {
        case .noAccounts:
            String(localized: "No Accounts", comment: "Alert title when there is no account to send a shared item from")
        case .unavailable:
            String(
                localized: "Couldn't Open Mail", comment: "Alert title when the share sheet can't read Goodmail's mail")
        case .waiting(.saveDraft):
            String(localized: "Not Saved Yet", comment: "Alert title when a shared draft will be saved later")
        case .waiting:
            String(localized: "Not Sent Yet", comment: "Alert title when a shared message will be sent later")
        case .signedOut(.saveDraft):
            String(
                localized: "Sign In to Save", comment: "Alert title when a shared draft waits for the account's sign-in"
            )
        case .signedOut:
            String(
                localized: "Sign In to Send",
                comment: "Alert title when a shared message waits for the account's sign-in")
        case .unconfirmed:
            String(localized: "Sending Not Confirmed", comment: "Alert title when the server didn't answer a send")
        case .refused(.saveDraft):
            String(localized: "Couldn't Save Draft", comment: "Alert title when the server refused a shared draft")
        case .refused, .notKept, .mayHaveGone:
            String(localized: "Couldn't Send", comment: "Alert title when a shared message didn't go")
        }
    }

    var message: String {
        switch self {
        case .noAccounts:
            String(
                localized: "Add an account in Goodmail, then share again.",
                comment: "Alert when there is no account to send a shared item from")
        case .unavailable:
            String(
                localized: "Open Goodmail once, then share again.",
                comment: "Alert when the share sheet can't read Goodmail's mail")
        case .waiting(.saveDraft):
            String(
                localized: "Goodmail couldn't reach your mail server. It will save this draft the next time it can.",
                comment: "Alert when a shared draft will be saved later")
        case .waiting:
            String(
                localized: "Goodmail couldn't reach your mail server. It will send this message the next time it can.",
                comment: "Alert when a shared message will be sent later")
        case .signedOut(.saveDraft):
            String(
                localized:
                    "This account isn't signed in on this device. Sign in again in Goodmail and it will save this draft.",
                comment: "Alert when a shared draft waits for the account's sign-in")
        case .signedOut:
            String(
                localized:
                    "This account isn't signed in on this device. Sign in again in Goodmail and it will send this message.",
                comment: "Alert when a shared message waits for the account's sign-in")
        case .unconfirmed:
            String(
                localized:
                    "The connection dropped before the server answered. Goodmail will check whether it went, and keep it for you to send again if it didn't.",
                comment: "Alert when the server didn't answer a send from the share sheet")
        case .refused:
            String(
                localized: "The server refused it. You'll find it in Goodmail, to fix and try again.",
                comment: "Alert when the server refused a shared message or draft")
        case .mayHaveGone:
            String(
                localized: "It may have gone anyway. Check your Sent mailbox before you send it again.",
                comment: "Alert when a shared message's send couldn't be confirmed or kept for later")
        case .notKept:
            String(
                localized: "Goodmail couldn't keep this message. Try again.",
                comment: "Alert when a shared message could be neither sent nor kept for later")
        }
    }
}
