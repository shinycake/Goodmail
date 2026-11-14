import Foundation
import MailCore

#if canImport(FoundationXML)
    import FoundationXML
#endif

/// A Thunderbird autoconfig file (`clientConfig`, version 1.1): the servers a provider offers, best first.
struct AutoconfigFile: Equatable {
    struct Server: Equatable {
        var type: String
        var host: String
        var port: UInt16
        /// `SSL`, `STARTTLS` or `plain`.
        var socketType: String
        /// A template, such as `%EMAILADDRESS%`.
        var username: String
        /// `password-cleartext`, `OAuth2` and the rest.
        var authentications: [String]
    }

    var incoming: [Server]
    var outgoing: [Server]

    init?(parsing data: Data) {
        let reader = Reader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse(), !reader.incoming.isEmpty || !reader.outgoing.isEmpty else { return nil }
        incoming = reader.incoming
        outgoing = reader.outgoing
    }

    /// The first IMAP and the first SMTP server that take a password over TLS. Goodmail doesn't log in with OAuth
    /// here, or send a password in the clear.
    func settings(for address: Address) -> MailServerSettings? {
        guard let imap = incoming.first(where: { $0.type == "imap" && $0.isUsable }),
            let smtp = outgoing.first(where: { $0.type == "smtp" && $0.isUsable }),
            let imapServer = imap.server, let smtpServer = smtp.server
        else { return nil }
        return MailServerSettings(imap: imapServer, smtp: smtpServer, username: imap.username(for: address))
    }
}

extension AutoconfigFile.Server {
    fileprivate var isUsable: Bool {
        server != nil && (authentications.isEmpty || authentications.contains("password-cleartext"))
    }

    fileprivate var server: MailServer? {
        let security: MailServer.Security? =
            switch socketType.uppercased() {
            case "SSL", "TLS": .tls
            case "STARTTLS": .startTLS
            default: nil
            }
        return security.map { MailServer(host: host, port: port, security: $0) }
    }

    /// The template filled in: `%EMAILADDRESS%`, `%EMAILLOCALPART%` and `%EMAILDOMAIN%`.
    fileprivate func username(for address: Address) -> String {
        username.replacing("%EMAILADDRESS%", with: address.email)
            .replacing("%EMAILLOCALPART%", with: address.localPart)
            .replacing("%EMAILDOMAIN%", with: address.domain)
    }
}

/// Collects `incomingServer` and `outgoingServer` elements. Lives only inside one synchronous `parse()`.
private final class Reader: NSObject, XMLParserDelegate {
    private(set) var incoming: [AutoconfigFile.Server] = []
    private(set) var outgoing: [AutoconfigFile.Server] = []
    private var current: AutoconfigFile.Server?
    private var text = ""

    func parser(
        _ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        text = ""
        if element == "incomingServer" || element == "outgoingServer" {
            current = AutoconfigFile.Server(
                type: attributes["type"]?.lowercased() ?? "", host: "", port: 0, socketType: "", username: "",
                authentications: [])
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, didEndElement element: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = ""
        switch element {
        case "hostname": current?.host = value
        case "port": current?.port = UInt16(value) ?? 0
        case "socketType": current?.socketType = value
        case "username": current?.username = value
        case "authentication": current?.authentications.append(value)
        case "incomingServer":
            if let server = current, server.isComplete { incoming.append(server) }
            current = nil
        case "outgoingServer":
            if let server = current, server.isComplete { outgoing.append(server) }
            current = nil
        default: break
        }
    }
}

extension AutoconfigFile.Server {
    fileprivate var isComplete: Bool { !host.isEmpty && port != 0 }
}
