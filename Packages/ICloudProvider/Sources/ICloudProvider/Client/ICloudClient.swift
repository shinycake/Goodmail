import Foundation
import MailCore

/// iCloud Mail as a `MailProvider`, over IMAP with an app-specific password. No IMAP type leaves this module (ADR-005).
///
/// IMAP keeps messages in folders; Goodmail reads threads with labels. So the client
/// - groups messages into threads by their headers (`threadIDs(for:)`) and remembers each message's thread in the
///   `MessageIndexStore`, because IMAP reports changes by message;
/// - gives a message its folder's label (`Folders`), STARRED for `\Flagged` and UNREAD without `\Seen`;
/// - takes every folder's STATUS as the cursor, and reads what changed since with CONDSTORE and QRESYNC;
/// - sends over SMTP, and files sent mail and drafts with APPEND.
public struct ICloudClient: MailProvider {
    static let imapHost = "imap.mail.me.com"
    static let smtpHost = "smtp.mail.me.com"

    let accountID: AccountID
    let session: IMAPSession
    let smtp: SMTPClient
    let index: any MessageIndexStore
    /// Messages per page of threads.
    let pageSize: Int

    #if canImport(Network)
        /// `email` is the iCloud address; `appPassword` one made at account.apple.com, since iCloud's IMAP doesn't
        /// take the Apple Account password.
        public init(accountID: AccountID, email: String, appPassword: String, index: any MessageIndexStore) {
            let credentials = ICloudCredentials(user: email, password: appPassword)
            self.init(
                accountID: accountID,
                session: IMAPSession(credentials: credentials) { TLSTransport(host: Self.imapHost, port: 993) },
                smtp: SMTPClient(credentials: credentials) { StreamTransport(host: Self.smtpHost, port: 587) },
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
            var statuses: [String: IMAPFolderStatus] = [:]
            for folder in Folders(try await connection.mailboxes()).all {
                statuses[folder.wireName] = try await connection.status(of: folder.wireName)
            }
            return ICloudCursor(folders: statuses).rawValue
        }
    }

    /// Reads the query's folders in turn, newest UID first, so a page holds one folder's messages. Text search
    /// isn't supported yet.
    public func threads(matching query: ThreadQuery, pageToken: String?) async throws -> ThreadPage {
        guard query.text == nil else { throw ICloudError.unsupported }
        let token = try pageToken.map(ICloudPageToken.init) ?? ICloudPageToken(folder: 0, position: nil)
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
                    ? ICloudPageToken(
                        folder: token.folder,
                        position: .init(uidValidity: selection.uidValidity, belowUID: page.first ?? 1))
                    : ICloudPageToken(folder: token.folder + 1, position: nil)
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

    /// iCloud keeps signatures on each device, out of IMAP's reach.
    public func signature() async throws -> String { "" }
}

/// What the iCloud client can't do yet: search by text.
public enum ICloudError: Error, Equatable {
    case unsupported
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
            flag: flag)
    }

    fileprivate func contains(_ header: IMAPMessageHeader) -> Bool {
        (since.map { header.receivedAt >= $0 } ?? true) && (before.map { header.receivedAt < $0 } ?? true)
    }
}
