#if DEBUG
    import Foundation
    import GmailProvider
    import MailCore
    import OSLog

    /// Developer tools for the test account (ADR-010), run from the simulator against a checkout of the repo:
    ///
    /// - `-GoodmailSeedTestMail <repo>/TestMail` files the corpus into the first account's Inbox with
    ///   `messages.insert`, which sends nothing. Threads already there (matched by Message-ID) are skipped.
    /// - `-GoodmailRecordFixtures <dir>`, alongside it, then writes Gmail's `format=full` response for each corpus thread, and the data of
    ///   its attachments, as fixtures. `scripts/record-fixtures` runs it and scrubs the account's address.
    enum TestMailTools {
        private static let log = Logger(subsystem: "com.idanbirman.goodmail", category: "test-mail")

        static func runIfRequested(model: AppModel) {
            let defaults = UserDefaults.standard
            guard let account = model.accounts.first(where: { $0.service == .gmail }) else { return }
            let corpus = defaults.string(forKey: "GoodmailSeedTestMail").map { URL(filePath: $0) }
            let fixtures = defaults.string(forKey: "GoodmailRecordFixtures").map { URL(filePath: $0) }
            guard let corpus else { return }
            Task {
                do {
                    let gmail = DebugGmail(
                        session: OAuthSession(accountID: account.id, client: .gmail, keychain: Keychain()))
                    try await seed(corpus, into: gmail)
                    if let fixtures { try await record(corpus, into: fixtures, from: gmail) }
                    log.notice("done")
                } catch {
                    log.error("Failed: \(error, privacy: .public)")
                }
            }
        }

        private static func threads(in corpus: URL) throws -> [(name: String, messages: [URL])] {
            try FileManager.default.contentsOfDirectory(at: corpus, includingPropertiesForKeys: nil)
                .filter(\.hasDirectoryPath)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .map { folder in
                    let messages = try FileManager.default.contentsOfDirectory(
                        at: folder, includingPropertiesForKeys: nil
                    )
                    .filter { $0.pathExtension == "eml" }
                    .sorted { $0.lastPathComponent < $1.lastPathComponent }
                    return (folder.lastPathComponent, messages)
                }
        }

        private static func seed(_ corpus: URL, into gmail: DebugGmail) async throws {
            for thread in try threads(in: corpus) {
                let first = try Data(contentsOf: thread.messages[0])
                if try await gmail.threadID(forMessageID: messageID(in: first)) != nil {
                    log.notice("\(thread.name, privacy: .public) already seeded")
                    continue
                }
                var threadID: String?
                for url in thread.messages {
                    threadID = try await gmail.insert(raw: Data(contentsOf: url), threadID: threadID)
                }
                log.notice("seeded \(thread.name, privacy: .public)")
            }
        }

        private static func record(_ corpus: URL, into directory: URL, from gmail: DebugGmail) async throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for thread in try threads(in: corpus) {
                let first = try Data(contentsOf: thread.messages[0])
                guard let threadID = try await gmail.threadID(forMessageID: messageID(in: first)) else {
                    log.notice("\(thread.name, privacy: .public) isn't seeded; skipping")
                    continue
                }
                let json = try await gmail.get("users/me/threads/\(threadID)", query: ["format": "full"])
                try json.write(to: directory.appending(path: "\(thread.name).json"))
                for (messageID, partID, attachmentID) in attachments(in: json) {
                    let data = try await gmail.get("users/me/messages/\(messageID)/attachments/\(attachmentID)")
                    try data.write(to: directory.appending(path: "\(thread.name)-part-\(partID).json"))
                }
                log.notice("recorded \(thread.name, privacy: .public)")
            }
        }

        private static func messageID(in raw: Data) -> String {
            let headers = String(decoding: raw.prefix(4096), as: UTF8.self)
            let line = headers.split(separator: "\n").first { $0.lowercased().hasPrefix("message-id:") } ?? ""
            return line.dropFirst("Message-ID:".count).trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
        }

        /// `(messageID, partID, attachmentID)` for every part whose data Gmail left out of the thread response.
        /// Attachment IDs change between responses, so fixtures are named by the stable part ID.
        private static func attachments(in thread: Data) -> [(String, String, String)] {
            guard let root = try? JSONSerialization.jsonObject(with: thread) as? [String: Any],
                let messages = root["messages"] as? [[String: Any]]
            else { return [] }
            func walk(_ part: [String: Any], _ messageID: String) -> [(String, String, String)] {
                let attachmentID = (part["body"] as? [String: Any])?["attachmentId"] as? String
                let own = attachmentID.map { [(messageID, part["partId"] as? String ?? "", $0)] } ?? []
                return own + ((part["parts"] as? [[String: Any]]) ?? []).flatMap { walk($0, messageID) }
            }
            return messages.flatMap { message in
                guard let id = message["id"] as? String, let payload = message["payload"] as? [String: Any]
                else { return [(String, String, String)]() }
                return walk(payload, id)
            }
        }
    }

    /// Bare Gmail REST for the tools above; the app proper goes through `GmailClient`.
    struct DebugGmail {
        struct Failure: Error {
            let status: Int
            let body: String
        }

        let session: OAuthSession

        func get(_ path: String, query: [String: String] = [:]) async throws -> Data {
            let url = GmailConfiguration.apiBaseURL.appending(path: path)
                .appending(queryItems: query.map { URLQueryItem(name: $0.key, value: $0.value) })
            return try await send(URLRequest(url: url))
        }

        func threadID(forMessageID id: String) async throws -> String? {
            let data = try await get("users/me/messages", query: ["q": "rfc822msgid:\(id)"])
            let list = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return (list?["messages"] as? [[String: Any]])?.first?["threadId"] as? String
        }

        /// Files `raw` in the Inbox, unread, and returns its thread ID. `datedByHeader` dates it by its Date header
        /// rather than now.
        func insert(raw: Data, threadID: String? = nil, datedByHeader: Bool = true) async throws -> String {
            let source = datedByHeader ? "dateHeader" : "receivedTime"
            var request = URLRequest(
                url: GmailConfiguration.apiBaseURL.appending(path: "users/me/messages")
                    .appending(queryItems: [URLQueryItem(name: "internalDateSource", value: source)]))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            var body: [String: Any] = [
                "raw": raw.base64EncodedString().replacingOccurrences(of: "+", with: "-")
                    .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: ""),
                "labelIds": ["INBOX", "UNREAD"],
            ]
            if let threadID { body["threadId"] = threadID }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            let response = try JSONSerialization.jsonObject(with: try await send(request)) as? [String: Any]
            guard let id = response?["threadId"] as? String else { throw URLError(.badServerResponse) }
            return id
        }

        private func send(_ request: URLRequest) async throws -> Data {
            var request = request
            request.setValue("Bearer \(try await session.validAccessToken())", forHTTPHeaderField: "Authorization")
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = response.statusCode
            guard (200..<300).contains(status) else {
                throw Failure(status: status, body: String(decoding: data, as: UTF8.self))
            }
            return data
        }
    }
#endif
