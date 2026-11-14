import MailCore
import SwiftUI

/// The account's incoming (IMAP) and outgoing (SMTP) servers, and the user name both log in with.
struct ServerSettingsSections: View {
    @Binding var settings: MailServerSettings

    var body: some View {
        Section {
            ServerFields(server: $settings.imap, defaults: .imap)
        } header: {
            Text(
                "Incoming Mail Server (IMAP)", tableName: "OtherAccount", bundle: .module,
                comment: "Other account: the section for the IMAP server")
        }
        Section {
            ServerFields(server: $settings.smtp, defaults: .smtp)
        } header: {
            Text(
                "Outgoing Mail Server (SMTP)", tableName: "OtherAccount", bundle: .module,
                comment: "Other account: the section for the SMTP server")
        }
        Section {
            LabeledContent {
                TextField(
                    OtherAccountSignInView.string("User Name", "Other account: the name both servers log in with"),
                    text: $settings.username, prompt: Text(verbatim: "name@example.com")
                )
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .multilineTextAlignment(.trailing)
            } label: {
                Text(
                    "User Name", tableName: "OtherAccount", bundle: .module,
                    comment: "Other account: the name both servers log in with")
            }
        } footer: {
            Text(
                "Usually your email address, or the part before the @.", tableName: "OtherAccount", bundle: .module,
                comment: "Other account: what the user name usually is")
        }
    }
}

/// A protocol's standard ports for each security, so changing the security moves a port that was standard to the
/// other, and an example host name.
nonisolated struct ServerDefaults: Equatable, Sendable {
    var tls: UInt16
    var startTLS: UInt16

    /// A host name to show in an empty field.
    var exampleHost: String

    static let imap = ServerDefaults(tls: 993, startTLS: 143, exampleHost: "imap.example.com")
    static let smtp = ServerDefaults(tls: 465, startTLS: 587, exampleHost: "smtp.example.com")

    func port(for security: MailServer.Security) -> UInt16 {
        switch security {
        case .tls: tls
        case .startTLS: startTLS
        }
    }

    /// `server` with `security`, on that security's standard port when it was on the old one's.
    func server(_ server: MailServer, changingTo security: MailServer.Security) -> MailServer {
        var changed = server
        if server.port == port(for: server.security) { changed.port = port(for: security) }
        changed.security = security
        return changed
    }
}

private struct ServerFields: View {
    @Binding var server: MailServer
    let defaults: ServerDefaults

    var body: some View {
        LabeledContent {
            TextField(
                OtherAccountSignInView.string(
                    "Host Name", "Other account: a server's host name, such as imap.example.com"),
                text: $server.host, prompt: Text(verbatim: defaults.exampleHost)
            )
            .textContentType(.URL)
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .multilineTextAlignment(.trailing)
        } label: {
            Text(
                "Host Name", tableName: "OtherAccount", bundle: .module,
                comment: "Other account: a server's host name, such as imap.example.com")
        }
        LabeledContent {
            TextField(value: $server.port, format: .number.grouping(.never)) {
                Text(verbatim: "\(defaults.port(for: server.security))")
            }
            .keyboardType(.numberPad)
            .multilineTextAlignment(.trailing)
        } label: {
            Text("Port", tableName: "OtherAccount", bundle: .module, comment: "Other account: a server's port")
        }
        Picker(
            selection: Binding(
                get: { server.security },
                set: { server = defaults.server(server, changingTo: $0) })
        ) {
            Text(verbatim: "SSL/TLS").tag(MailServer.Security.tls)
            Text(verbatim: "STARTTLS").tag(MailServer.Security.startTLS)
        } label: {
            Text(
                "Security", tableName: "OtherAccount", bundle: .module,
                comment: "Other account: how the connection to a server is encrypted")
        }
    }
}
