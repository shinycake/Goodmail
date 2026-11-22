public import Foundation
public import MailCore

/// Where a link tapped in a message goes: a `mailto:` link is a new message in Goodmail, from the account reading
/// it, rather than one in another mail app; anything else opens outside.
nonisolated public enum MessageLink: Equatable, Sendable {
    case compose(Draft)
    case outside(URL)

    public init(_ url: URL, account: AccountID) {
        self = Draft(mailto: url, from: account).map(Self.compose) ?? .outside(url)
    }
}
