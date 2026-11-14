import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking  // URLRequest on Linux
#endif

/// Takes the reader off a mailing list the way the list's message offers (`Unsubscribe`). Sendable and stateless:
/// the request runs on the global executor, never the main actor, and a mail goes out through `MailCommands` like
/// any other send.
public struct ListUnsubscriber: Sendable {
    /// What is left for the reader once `unsubscribe` returns.
    public enum Outcome: Equatable, Sendable {
        /// The list has the request; nothing more to do.
        case done
        /// The list wants its page opened to finish.
        case openPage(URL)
    }

    public enum Failure: Error, Equatable {
        /// The list's server answered the one-click request with this status.
        case refused(status: Int)
    }

    private let http: any HTTPClient
    private let commands: MailCommands

    /// `http` should keep no cookies or credentials: RFC 8058 asks one-click requests to carry none.
    public init(http: any HTTPClient, commands: MailCommands) {
        self.http = http
        self.commands = commands
    }

    /// Unsubscribes `account`'s reader through `unsubscribe`, off the caller's actor. Throws when the request can't be
    /// made or is refused.
    @concurrent
    public func unsubscribe(_ unsubscribe: Unsubscribe, account: AccountID) async throws -> Outcome {
        switch unsubscribe {
        case .oneClick(let url):
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpShouldHandleCookies = false
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("List-Unsubscribe=One-Click".utf8)
            let (_, response) = try await http.data(for: request)
            guard (200..<300).contains(response.statusCode) else {
                throw Failure.refused(status: response.statusCode)
            }
            return .done
        case .mail(let mailto):
            try await commands.send(Self.draft(for: mailto, account: account), after: .zero)
            return .done
        case .page(let url):
            return .openPage(url)
        }
    }

    /// The message the list asked for. A list that names no subject gets "unsubscribe", which list servers read.
    static func draft(for mailto: Unsubscribe.Mailto, account: AccountID) -> Draft {
        let html = mailto.body
            .replacing("&", with: "&amp;").replacing("<", with: "&lt;").replacing(">", with: "&gt;")
            .replacing("\n", with: "<br>")
        return Draft(
            accountID: account,
            to: mailto.to.map { Contact(name: nil, address: $0) },
            subject: mailto.subject.isEmpty ? "unsubscribe" : mailto.subject,
            body: MessageBody(html: html, plain: mailto.body))
    }
}
