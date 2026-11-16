import Foundation
import Testing

@testable import MailCore

/// A conversation saved as one mbox file (the mboxrd variant) that Apple Mail, Thunderbird and mutt open.
struct MboxArchiveTests {
    private let date = Date(timeIntervalSince1970: 1_762_421_400)  // Thu Nov  6 09:30:00 2025 UTC

    @Test func eachMessageStartsWithAFromLineNamingItsSenderAndUTCDate() {
        let archive = MboxArchive.data(for: [
            .init(source: Data("Subject: Hi\r\n\r\nHello\r\n".utf8), sender: "dana@example.com", date: date)
        ])
        #expect(
            String(decoding: archive, as: UTF8.self)
                == "From dana@example.com Thu Nov  6 09:30:00 2025\nSubject: Hi\n\nHello\n\n")
    }

    @Test func bodyLinesThatLookLikeAFromLineAreQuotedOneLevelDeeper() {
        let source = "Subject: Hi\n\nFrom here on\n>From the top\nNot From\n"
        let archive = MboxArchive.data(for: [.init(source: Data(source.utf8), sender: "a@b.c", date: date)])
        #expect(
            String(decoding: archive, as: UTF8.self).hasSuffix(
                "Subject: Hi\n\n>From here on\n>>From the top\nNot From\n\n"))
    }

    @Test func messagesFollowEachOtherAndALastLineWithoutABreakGetsOne() {
        let archive = MboxArchive.data(for: [
            .init(source: Data("Subject: One\n\nfirst".utf8), sender: "a@b.c", date: date),
            .init(source: Data("Subject: Two\n\nsecond\n".utf8), sender: "", date: date),
        ])
        #expect(
            String(decoding: archive, as: UTF8.self)
                == "From a@b.c Thu Nov  6 09:30:00 2025\nSubject: One\n\nfirst\n\n"
                + "From MAILER-DAEMON Thu Nov  6 09:30:00 2025\nSubject: Two\n\nsecond\n\n")
    }

    @Test func bytesThatAreNotUTF8PassThroughUntouched() {
        let latin1: [UInt8] = Array("Subject: Caf".utf8) + [0xE9] + Array("\n\nbody\n".utf8)
        let archive = MboxArchive.data(for: [.init(source: Data(latin1), sender: "a@b.c", date: date)])
        #expect(archive.contains(0xE9))
    }

    @Test func twoDigitDaysAreNotPadded() {
        let later = date.addingTimeInterval(10 * 86_400)
        let archive = MboxArchive.data(for: [.init(source: Data("x\n".utf8), sender: "a@b.c", date: later)])
        #expect(String(decoding: archive, as: UTF8.self).hasPrefix("From a@b.c Sun Nov 16 09:30:00 2025\n"))
    }
}
