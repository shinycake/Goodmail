public import MailCore

// What the IMAP side says when the server, or the Keychain, no longer has a login that works, so the account asks to
// have its password typed again rather than waiting for the server to come round.

extension IMAPError: SignInRejecting {
    var rejectsSignIn: Bool { self == .authenticationFailed }
}

extension IMAPSignIn.Failure: SignInRejecting {
    public var rejectsSignIn: Bool {
        switch self {
        case .refused, .signedOut: true
        case .insecure, .unreachable: false
        }
    }
}

extension ICloudSignIn.Failure: SignInRejecting {
    public var rejectsSignIn: Bool {
        switch self {
        case .wrongPassword, .signedOut: true
        }
    }
}
