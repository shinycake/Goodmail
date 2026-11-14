/// A server an account connects to, and how the connection is encrypted. Goodmail never logs in, or reads mail,
/// over a connection without TLS.
public struct MailServer: Codable, Hashable, Sendable {
    public enum Security: String, Codable, CaseIterable, Hashable, Sendable {
        /// TLS from the first byte, as IMAP's port 993 and SMTP's 465 serve it.
        case tls
        /// Plain until STARTTLS turns on TLS (RFC 2595, RFC 3207), as IMAP's port 143 and SMTP's 587 serve it. The
        /// connection is given up when the server doesn't offer STARTTLS.
        case startTLS
    }

    public var host: String
    public var port: UInt16
    public var security: Security

    public init(host: String, port: UInt16, security: Security) {
        self.host = host
        self.port = port
        self.security = security
    }
}

/// Where an account reads its mail and sends it, and the name it logs in to both with, which is usually its
/// address.
public struct MailServerSettings: Codable, Hashable, Sendable {
    public var imap: MailServer
    public var smtp: MailServer
    public var username: String

    public init(imap: MailServer, smtp: MailServer, username: String) {
        self.imap = imap
        self.smtp = smtp
        self.username = username
    }

    /// iCloud Mail, as Apple documents its servers: IMAP on 993 over TLS, SMTP on 587 with STARTTLS, both logged in
    /// to with the address.
    public static func icloud(email: String) -> Self {
        Self(imap: .icloudIMAP, smtp: .icloudSMTP, username: email)
    }
}

extension MailServer {
    static let icloudIMAP = MailServer(host: "imap.mail.me.com", port: 993, security: .tls)
    static let icloudSMTP = MailServer(host: "smtp.mail.me.com", port: 587, security: .startTLS)
}
