import MailCore
import Testing

@testable import MailUI

struct ServerSettingsTests {
    @Test func changingTheSecurityMovesAStandardPortToTheOthersStandardPort() {
        let imap = MailServer(host: "imap.example.com", port: 993, security: .tls)
        #expect(ServerDefaults.imap.server(imap, changingTo: .startTLS).port == 143)
        let smtp = MailServer(host: "smtp.example.com", port: 587, security: .startTLS)
        #expect(ServerDefaults.smtp.server(smtp, changingTo: .tls).port == 465)
    }

    @Test func aPortTheReaderTypedStaysWhenTheSecurityChanges() {
        let custom = MailServer(host: "mail.example.com", port: 2525, security: .startTLS)
        let changed = ServerDefaults.smtp.server(custom, changingTo: .tls)
        #expect(changed.port == 2525)
        #expect(changed.security == .tls)
    }
}
