/// The iCloud address and an app-specific password, which IMAP and SMTP both log in with.
struct ICloudCredentials: Sendable {
    var user: String
    var password: String
}
