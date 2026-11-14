import Foundation
import MailCore

/// Gmail's vacation responder (`users.settings.vacation`), under the `gmail.settings.basic` scope.
extension GmailClient: AutoReplying {
    public var autoReplyHasSubject: Bool { true }

    public func autoReply() async throws -> AutoReply {
        let vacation: GmailVacation = try await send("users/me/settings/vacation")
        return vacation.autoReply
    }

    public func setAutoReply(_ reply: AutoReply) async throws {
        let _: GmailVacation = try await send(
            "users/me/settings/vacation", method: "PUT", body: GmailVacation(reply))
    }
}

/// `users.settings.vacation`: times are milliseconds since 1970, as strings.
struct GmailVacation: Codable, Equatable {
    var enableAutoReply: Bool?
    var responseSubject: String?
    var responseBodyPlainText: String?
    var responseBodyHtml: String?
    var restrictToContacts: Bool?
    var restrictToDomain: Bool?
    var startTime: String?
    var endTime: String?

    init(_ reply: AutoReply) {
        responseSubject = reply.subject
        responseBodyPlainText = reply.message
        restrictToContacts = reply.contactsOnly
        restrictToDomain = false
        switch reply.schedule {
        case .off:
            enableAutoReply = false
        case .on:
            enableAutoReply = true
        case .between(let interval):
            enableAutoReply = true
            startTime = Self.milliseconds(interval.start)
            endTime = Self.milliseconds(interval.end)
        }
    }

    /// A reply with a start but no end runs from that start on, which reads as on: Gmail holds it until then.
    var autoReply: AutoReply {
        let schedule: AutoReply.Schedule =
            if enableAutoReply != true {
                .off
            } else if let start = startTime.flatMap(Self.date), let end = endTime.flatMap(Self.date), start <= end {
                .between(DateInterval(start: start, end: end))
            } else {
                .on
            }
        let message =
            responseBodyPlainText.flatMap { $0.isEmpty ? nil : $0 }
            ?? HTMLEntities.plainText(fromHTML: responseBodyHtml ?? "")
        return AutoReply(
            schedule: schedule, subject: responseSubject ?? "", message: message,
            contactsOnly: restrictToContacts ?? false)
    }

    private static func milliseconds(_ date: Date) -> String {
        String(Int64((date.timeIntervalSince1970 * 1000).rounded()))
    }

    private static func date(_ milliseconds: String) -> Date? {
        Double(milliseconds).map { Date(timeIntervalSince1970: $0 / 1000) }
    }
}
