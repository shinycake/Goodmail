import MailCore

extension MailServerSettings {
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
