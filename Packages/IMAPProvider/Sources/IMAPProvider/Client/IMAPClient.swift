import Foundation
public import MailCore

/// A mail account on an IMAP and SMTP server as a `MailProvider`, as iCloud Mail serves one. No IMAP type leaves this
/// module (ADR-005).
///
/// IMAP keeps messages in folders; Goodmail reads threads with labels. So the client
/// - groups messages into threads by their headers (`threadIDs(for:)`) and remembers each message's thread in the
///   `MessageIndexStore`, because IMAP reports changes by message;
/// - gives a message its folder's label (`Folders`), STARRED for `\Flagged` and UNREAD without `\Seen`;
/// - takes every folder's STATUS as the cursor, and reads what changed since with CONDSTORE and QRESYNC;
/// - sends over SMTP, and files sent mail and drafts with APPEND.
public struct IMAPClient: MailProvider {
    let accountID: AccountID
    let session: IMAPSession
    let smtp: SMTPClient
    let index: any MessageIndexStore
    /// Messages per page of threads.
    let pageSize: Int
    /// Each message's source for a moment after it downloads, so its inline images don't download it again each.
    let sources = RecentSources()

    #if canImport(Network)
        /// Reads mail from `settings.imap` and sends it through `settings.smtp`, logging in to both with
        /// `settings.username` and `password`.
        public init(
            accountID: AccountID, settings: MailServerSettings, password: String, index: any MessageIndexStore
        ) {
            let credentials = IMAPCredentials(user: settings.username, password: password)
            self.init(
                accountID: accountID,
                session: IMAPSession(credentials: credentials, security: settings.imap.security) {
                    StreamTransport(to: settings.imap)
                },
                smtp: SMTPClient(credentials: credentials, security: settings.smtp.security) {
                    StreamTransport(to: settings.smtp)
                },
                index: index)
        }
    #endif

    init(
        accountID: AccountID, session: IMAPSession, smtp: SMTPClient, index: any MessageIndexStore, pageSize: Int = 50
    ) {
        self.accountID = accountID
        self.session = session
        self.smtp = smtp
        self.index = index
        self.pageSize = pageSize
    }

    public func labels() async throws -> [MailLabel] {
        try await session.run { connection in Folders(try await connection.mailboxes()).labels }
    }

    public func currentCursor() async throws -> String {
        try await session.run { connection in
            let folders = Folders(try await connection.mailboxes()).all
            var statuses: [String: IMAPFolderStatus] = [:]
            for folder in folders {
                statuses[folder.wireName] = try await connection.status(of: folder.wireName)
            }
            let marks = try await flagMarks(of: folders, statuses: statuses, on: connection)
            return IMAPCursor(folders: statuses, marks: marks).rawValue
        }
    }

    /// Reads the query's folders in turn, newest UID first, so a page holds one folder's messages. Text matches
    /// every word anywhere in a message, as iCloud's server search finds it.
    public func threads(matching query: ThreadQuery, pageToken: String?) async throws -> ThreadPage {
        let token = try pageToken.map(IMAPPageToken.init) ?? IMAPPageToken(folder: 0, position: nil)
        return try await session.run { connection in
            let folders = Folders(try await connection.mailboxes())
            let (targets, flag) = folders.search(for: query.label)
            var token = token
            while token.folder < targets.count {
                let folder = targets[token.folder]
                let selection = try await connection.select(folder.wireName)
                let below = token.position.flatMap { $0.uidValidity == selection.uidValidity ? $0.belowUID : nil }
                let found = below == 1 ? [] : try await connection.searchUIDs(query.search(flag: flag, below: below))
                let page = found.suffix(pageSize)
                token =
                    found.count > pageSize
                    ? IMAPPageToken(
                        folder: token.folder,
                        position: .init(uidValidity: selection.uidValidity, belowUID: page.first ?? 1))
                    : IMAPPageToken(folder: token.folder + 1, position: nil)
                guard !page.isEmpty else { continue }
                let messages = try await connection.headers(of: Array(page)).filter(query.contains).map {
                    FolderMessage(folder: folder, uidValidity: selection.uidValidity, header: $0)
                }
                let threadOf = try threadIDs(for: messages)
                let fetch = try await threads(Set(threadOf.values), known: messages, in: folders, on: connection)
                return ThreadPage(
                    threads: fetch.found.sorted { $0.date > $1.date },
                    nextPageToken: token.folder < targets.count ? token.rawValue : nil)
            }
            return ThreadPage(threads: [], nextPageToken: nil)
        }
    }

    public func threads(withIDs ids: [String]) async throws -> ThreadFetch {
        try await session.run { connection in
            let folders = Folders(try await connection.mailboxes())
            return try await threads(Set(ids), known: [], in: folders, on: connection)
        }
    }

    /// iCloud keeps contacts in CardDAV, not in mail. The address book still learns the people who wrote.
    public func contacts() async throws -> [Contact] { [] }
}

extension ThreadQuery {
    /// IMAP dates are days in the server's time zone, so the search takes a day either side and `contains(_:)` cuts
    /// the result to the exact times.
    fileprivate func search(flag: IMAPSearch.Flag?, below: UInt32?) -> IMAPSearch {
        let day: TimeInterval = 86_400
        return IMAPSearch(
            uids: below.map { 1...($0 - 1) },
            since: since?.addingTimeInterval(-day),
            before: before?.addingTimeInterval(day),
            flag: flag,
            text: text)
    }

    fileprivate func contains(_ header: IMAPMessageHeader) -> Bool {
        (since.map { header.receivedAt >= $0 } ?? true) && (before.map { header.receivedAt < $0 } ?? true)
    }
}
