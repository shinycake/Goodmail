/// The user name and password that IMAP and SMTP both log in with.
struct IMAPCredentials: Sendable {
    var user: String
    var password: String
}
