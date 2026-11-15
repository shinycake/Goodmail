import MailCore
import Testing

@testable import IMAPProvider

/// A refused password, or one the Keychain lost, asks the reader to type it again; a server that can't be reached
/// doesn't.
struct SignInRejectionTests {
    @Test(arguments: [
        IMAPError.authenticationFailed as any Error, IMAPSignIn.Failure.refused(.imap), IMAPSignIn.Failure.signedOut,
        ICloudSignIn.Failure.wrongPassword, ICloudSignIn.Failure.signedOut,
    ])
    func aRefusedOrMissingLoginNeedsSigningInAgain(error: any Error) {
        #expect(AccountHealth.healthy.after(.failure(error), at: .now) == .needsSignIn)
    }

    @Test(arguments: [
        IMAPError.closed as any Error, IMAPError.insecure, IMAPSignIn.Failure.unreachable(.imap),
        IMAPSignIn.Failure.insecure(.smtp),
    ])
    func otherFailuresDoNot(error: any Error) {
        #expect(AccountHealth.healthy.after(.failure(error), at: .now) != .needsSignIn)
    }
}
