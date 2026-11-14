import MailCore

/// Where the Other Mail Account form stands, and the one place it moves on. The servers belong to the stages that
/// show or use them, so there are never servers without a stage that needs them, or a stage that needs them without.
nonisolated enum OtherAccountStage: Equatable, Sendable {
    /// Why the last try failed, as the form explains it.
    enum Failure: Equatable, Sendable {
        case signIn(OtherAccountSignInFailure)
        /// Anything else, already in words.
        case other(String)
    }

    /// The name, address and password.
    case account(failure: Failure?)
    /// Looking the servers up.
    case discovering
    /// Logging in to the servers the lookup found, before showing them.
    case signingIn(MailServerSettings)
    /// The servers, to fill in or correct. `found` says whether they came from the lookup.
    case servers(MailServerSettings, found: Bool, failure: Failure?)
    /// Logging in to the servers as typed.
    case checking(MailServerSettings, found: Bool)

    var isBusy: Bool {
        switch self {
        case .discovering, .signingIn, .checking: true
        case .account, .servers: false
        }
    }

    var isOnAccount: Bool {
        if case .account = self { true } else { false }
    }

    var failure: Failure? {
        switch self {
        case .account(let failure), .servers(_, _, let failure): failure
        case .discovering, .signingIn, .checking: nil
        }
    }

    /// The servers the form shows: while they're being filled in, and while they're checked.
    var shownServers: MailServerSettings? {
        switch self {
        case .servers(let settings, _, _), .checking(let settings, _): settings
        case .account, .discovering, .signingIn: nil
        }
    }

    /// Whether the lookup found nothing, so the form says so.
    var foundNoServers: Bool {
        switch self {
        case .servers(_, let found, _), .checking(_, let found): !found
        case .account, .discovering, .signingIn: false
        }
    }

    /// The stage `submit` moves to: the lookup from the account, the check from the servers once each is filled in.
    var submitted: OtherAccountStage? {
        switch self {
        case .account: .discovering
        case .servers(let settings, let found, _): settings.isFilledIn ? .checking(settings, found: found) : nil
        case .discovering, .signingIn, .checking: nil
        }
    }

    /// After the lookup: signing in with what it found, or asking for the servers, starting from `guess`.
    static func lookedUp(_ found: MailServerSettings?, guess: MailServerSettings) -> OtherAccountStage {
        found.map { .signingIn($0) } ?? .servers(guess, found: false, failure: nil)
    }

    /// After a sign-in failed. A password the found servers refused is asked for again, since those servers are most
    /// likely right; anything else shows the servers to correct.
    func failed(_ failure: Failure) -> OtherAccountStage {
        switch self {
        case .signingIn(let settings):
            if case .signIn(.refused) = failure { return .account(failure: failure) }
            return .servers(settings, found: true, failure: failure)
        case .checking(let settings, let found):
            return .servers(settings, found: found, failure: failure)
        case .account, .discovering, .servers:
            return self
        }
    }

    /// The servers as edited, kept with the rest of the stage. Only the servers stage takes edits.
    func editing(_ settings: MailServerSettings) -> OtherAccountStage {
        guard case .servers(_, let found, let failure) = self else { return self }
        return .servers(settings, found: found, failure: failure)
    }
}

extension MailServerSettings {
    /// Whether every field a sign-in needs has something in it.
    nonisolated var isFilledIn: Bool {
        !imap.host.isEmpty && !smtp.host.isEmpty && !username.isEmpty && imap.port != 0 && smtp.port != 0
    }
}
