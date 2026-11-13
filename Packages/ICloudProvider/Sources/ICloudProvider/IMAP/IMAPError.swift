/// Why an IMAP command failed.
enum IMAPError: Error, Equatable {
    /// The server rejected the user name or password.
    case authenticationFailed
    /// The server answered `NO`: it understood the command and refused it.
    case refused(IMAPStatus)
    /// The server answered `BAD`: it didn't understand the command.
    case invalid(IMAPStatus)
    /// The connection is closed, by the server's `BYE`, by `LOGOUT` or because the stream ended.
    case closed
    /// The command needs a state the connection isn't in, such as fetching before a mailbox is selected.
    case wrongState
    /// An argument can't be written as a quoted string.
    case unencodable
}
