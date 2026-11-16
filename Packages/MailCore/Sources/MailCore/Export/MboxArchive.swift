import Foundation

/// Messages saved as one mbox file, in the mboxrd variant: each message's raw source after a `From ` line naming
/// its sender and date, with body lines that read like a `From ` line quoted one level deeper so they can be told
/// apart. Lines end in LF, as mbox readers expect. Works on bytes, since a source needn't be UTF-8.
public enum MboxArchive {
    public struct Entry: Sendable {
        /// The message's RFC 5322 source, as the provider returned it.
        public let source: Data
        /// The envelope sender for the `From ` line. Empty becomes `MAILER-DAEMON`, as mbox writers do.
        public let sender: String
        public let date: Date

        public init(source: Data, sender: String, date: Date) {
            self.source = source
            self.sender = sender
            self.date = date
        }
    }

    public static func data(for entries: [Entry]) -> Data {
        var archive = Data()
        for entry in entries {
            let sender = entry.sender.isEmpty ? "MAILER-DAEMON" : entry.sender.filter { !$0.isWhitespace }
            archive.append(contentsOf: Array("From \(sender) \(asctime(entry.date))\n".utf8))
            for line in lines(of: entry.source) {
                if isFromLine(line) { archive.append(UInt8(ascii: ">")) }
                archive.append(contentsOf: line)
                archive.append(UInt8(ascii: "\n"))
            }
            archive.append(UInt8(ascii: "\n"))
        }
        return archive
    }

    /// The source's lines without their CR LF or LF, and no empty last line for a source that ends in a break.
    private static func lines(of source: Data) -> [ArraySlice<UInt8>] {
        var lines = Array(source).split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
        if lines.last?.isEmpty == true { lines.removeLast() }
        return lines.map { $0.last == UInt8(ascii: "\r") ? $0.dropLast() : $0 }
    }

    /// `From ` after any number of `>`, which a reader would otherwise take for the next message, or for one
    /// quoted by this rule that it must unquote.
    private static func isFromLine(_ line: ArraySlice<UInt8>) -> Bool {
        line.drop { $0 == UInt8(ascii: ">") }.starts(with: "From ".utf8)
    }

    /// "Thu Nov  6 09:30:00 2025": C's `asctime`, in UTC, which `From ` lines carry.
    static func asctime(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let parts = calendar.dateComponents([.weekday, .month, .day, .hour, .minute, .second, .year], from: date)
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        func two(_ value: Int?) -> String { String(format: "%02d", value ?? 0) }
        let day = String(format: "%2d", parts.day ?? 1)
        return "\(weekdays[(parts.weekday ?? 1) - 1]) \(months[(parts.month ?? 1) - 1]) \(day) "
            + "\(two(parts.hour)):\(two(parts.minute)):\(two(parts.second)) \(parts.year ?? 1970)"
    }
}
