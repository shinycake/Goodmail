import Foundation
import MailCore
import Testing

@testable import IMAPProvider

struct DiscoveryTests {
    /// Fastmail's entry in Mozilla's ISPDB, trimmed: a JMAP server Goodmail skips, IMAP over TLS and STARTTLS, and SMTP.
    static let fastmail = Data(
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <clientConfig version="1.1">
          <emailProvider id="fastmail.fm">
            <domain>fastmail.com</domain>
            <incomingServer type="jmap">
              <hostname>api.fastmail.com</hostname><port>443</port><socketType>SSL</socketType>
              <username>%EMAILADDRESS%</username><authentication>OAuth2</authentication>
            </incomingServer>
            <incomingServer type="imap">
              <hostname>imap.fastmail.com</hostname>
              <port>993</port>
              <socketType>SSL</socketType>
              <username>%EMAILADDRESS%</username>
              <authentication>OAuth2</authentication>
              <authentication>password-cleartext</authentication>
            </incomingServer>
            <incomingServer type="imap">
              <hostname>imap.fastmail.com</hostname><port>143</port><socketType>STARTTLS</socketType>
              <username>%EMAILADDRESS%</username><authentication>password-cleartext</authentication>
            </incomingServer>
            <outgoingServer type="smtp">
              <hostname>smtp.fastmail.com</hostname>
              <port>465</port>
              <socketType>SSL</socketType>
              <username>%EMAILADDRESS%</username>
              <authentication>password-cleartext</authentication>
            </outgoingServer>
          </emailProvider>
        </clientConfig>
        """.utf8)

    private func discovery(_ answers: [String: Data]) -> MailServerDiscovery {
        MailServerDiscovery { url in answers[url.absoluteString] }
    }

    @Test func theProvidersOwnFileComesBeforeMozillasDatabase() async {
        let own = String(decoding: Self.fastmail, as: UTF8.self).replacing(
            "imap.fastmail.com", with: "mail.own.example")
        let found = await discovery([
            "https://autoconfig.thunderbird.net/v1.1/example.com": Self.fastmail,
            "https://example.com/.well-known/autoconfig/mail/config-v1.1.xml": Data(own.utf8),
        ]).settings(for: " dana@Example.com")
        #expect(found?.imap == MailServer(host: "mail.own.example", port: 993, security: .tls))
        #expect(found?.username == "dana@Example.com")
    }

    @Test func mozillasDatabaseFillsInTheServersAndTheUserName() async {
        let found = await discovery(["https://autoconfig.thunderbird.net/v1.1/fastmail.com": Self.fastmail])
            .settings(for: "dana@fastmail.com")
        #expect(
            found
                == MailServerSettings(
                    imap: MailServer(host: "imap.fastmail.com", port: 993, security: .tls),
                    smtp: MailServer(host: "smtp.fastmail.com", port: 465, security: .tls),
                    username: "dana@fastmail.com"))
    }

    @Test func plainTextAndOAuthOnlyServersAreSkipped() throws {
        let xml = """
            <clientConfig><emailProvider>
            <incomingServer type="imap"><hostname>a</hostname><port>143</port><socketType>plain</socketType>
            <username>%EMAILLOCALPART%</username></incomingServer>
            <incomingServer type="imap"><hostname>b</hostname><port>993</port><socketType>SSL</socketType>
            <username>%EMAILLOCALPART%</username><authentication>OAuth2</authentication></incomingServer>
            <outgoingServer type="smtp"><hostname>c</hostname><port>587</port><socketType>STARTTLS</socketType>
            </outgoingServer>
            </emailProvider></clientConfig>
            """
        let file = try #require(AutoconfigFile(parsing: Data(xml.utf8)))
        #expect(file.settings(for: try #require(Address("dana@example.com"))) == nil)
        #expect(AutoconfigFile(parsing: Data("<html>not found</html>".utf8)) == nil)
    }

    @Test func theUserNameTemplateIsFilledIn() throws {
        let xml = """
            <clientConfig><emailProvider>
            <incomingServer type="imap"><hostname>imap.example.com</hostname><port>993</port>
            <socketType>SSL</socketType><username>%EMAILLOCALPART%</username></incomingServer>
            <outgoingServer type="smtp"><hostname>smtp.example.com</hostname><port>587</port>
            <socketType>STARTTLS</socketType><username>%EMAILLOCALPART%</username></outgoingServer>
            </emailProvider></clientConfig>
            """
        let file = try #require(AutoconfigFile(parsing: Data(xml.utf8)))
        #expect(file.settings(for: try #require(Address("dana@example.com")))?.username == "dana")
    }

    @Test func anUnknownDomainIsNilAndTheGuessUsesItsName() async {
        #expect(await discovery([:]).settings(for: "dana@example.org") == nil)
        #expect(await discovery([:]).settings(for: "not an address") == nil)
        let guess = MailServerDiscovery.guess(for: "dana@example.org")
        #expect(guess.imap == MailServer(host: "imap.example.org", port: 993, security: .tls))
        #expect(guess.smtp == MailServer(host: "smtp.example.org", port: 587, security: .startTLS))
    }

    @Test func theAddressGoesOnlyToTheProvidersOwnServer() throws {
        let urls = MailServerDiscovery.sources(for: try #require(Address("dana+news@example.com")))
        #expect(
            urls.map(\.absoluteString) == [
                "https://autoconfig.example.com/mail/config-v1.1.xml?emailaddress=dana%2Bnews@example.com",
                "https://example.com/.well-known/autoconfig/mail/config-v1.1.xml",
                "https://autoconfig.thunderbird.net/v1.1/example.com",
            ])
    }
}
