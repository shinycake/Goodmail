import Foundation
import MailCore

/// Where `changes(since:)` picks up: where every folder stood when the cursor was taken, keyed by wire name.
struct IMAPCursor: Equatable {
    /// A folder's STATUS counters, and how the next sync finds the messages whose flags changed since.
    struct Folder: Equatable {
        var uidValidity: UInt32
        var uidNext: UInt32
        var messageCount: Int
        var tracking: ChangeTracking

        /// The counters of `status`; its HIGHESTMODSEQ is the tracking's to carry.
        init(_ status: IMAPFolderStatus, tracking: ChangeTracking) {
            uidValidity = status.uidValidity
            uidNext = status.uidNext
            messageCount = status.messageCount
            self.tracking = tracking
        }

        /// Whether STATUS shows that nothing changed. Without CONDSTORE a flag change leaves STATUS as it was, so
        /// only the marks can tell.
        func isUnchanged(at now: IMAPFolderStatus) -> Bool {
            guard case .modSeq(let modSeq) = tracking else { return false }
            return now
                == IMAPFolderStatus(
                    uidValidity: uidValidity, uidNext: uidNext, messageCount: messageCount, highestModSeq: modSeq)
        }
    }

    /// How a sync finds the messages of a folder whose flags changed.
    enum ChangeTracking: Equatable {
        /// With CONDSTORE (RFC 7162), the server names what changed after the folder's HIGHESTMODSEQ, this one.
        case modSeq(UInt64)
        /// Without it, the read and starred flags of the folder's latest messages, by UID, to compare.
        case flagMarks([UInt32: FlagMarks])
    }

    var folders: [String: Folder]

    init(folders: [String: Folder]) {
        self.folders = folders
    }

    /// Throws `ProviderError.cursorExpired` for a cursor this client didn't write.
    init(_ rawValue: String) throws {
        guard let stored = try? JSONDecoder().decode(Stored.self, from: Data(rawValue.utf8)) else {
            throw ProviderError.cursorExpired
        }
        folders = Dictionary(
            uniqueKeysWithValues: stored.folders.map { name, status in
                // Earlier builds kept a mailbox without mod-sequences, whose STATUS says 0, at 0 (RFC 7162 §3.1.3).
                let tracking: ChangeTracking =
                    switch status.highestModSeq {
                    case nil, 0?: .flagMarks(stored.marks?[name] ?? [:])
                    case let modSeq?: .modSeq(modSeq)
                    }
                return (name, Folder(status, tracking: tracking))
            })
    }

    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Strings and integers always encode.
        return String(decoding: (try? encoder.encode(Stored(self))) ?? Data(), as: UTF8.self)
    }

    /// The cursor as it is kept, the shape earlier builds wrote, so their cursors read the same and theirs read
    /// these: a folder's status with a HIGHESTMODSEQ above 0 is `.modSeq`, and one without is `.flagMarks` from
    /// `marks`, which cursors from before marks were kept lack.
    private struct Stored: Codable {
        var folders: [String: IMAPFolderStatus]
        /// By wire name, then UID. Left out when no folder tracks marks.
        var marks: [String: [UInt32: FlagMarks]]?

        init(_ cursor: IMAPCursor) {
            folders = cursor.folders.mapValues { folder in
                let modSeq: UInt64? =
                    switch folder.tracking {
                    case .modSeq(let modSeq): modSeq
                    case .flagMarks: nil
                    }
                return IMAPFolderStatus(
                    uidValidity: folder.uidValidity, uidNext: folder.uidNext, messageCount: folder.messageCount,
                    highestModSeq: modSeq)
            }
            let marks = cursor.folders.compactMapValues { folder -> [UInt32: FlagMarks]? in
                guard case .flagMarks(let marks) = folder.tracking else { return nil }
                return marks
            }
            self.marks = marks.isEmpty ? nil : marks
        }
    }
}

/// Where a page of threads left off: the query's folders are read in turn, each newest UID first.
struct IMAPPageToken: Codable, Equatable {
    /// Where in a folder the next page starts.
    struct Position: Codable, Equatable {
        /// The UIDVALIDITY `belowUID` is a UID of. A folder whose UIDVALIDITY changed is read again from the top.
        var uidValidity: UInt32
        var belowUID: UInt32
    }

    /// The folder's index among the query's folders.
    var folder: Int
    /// `nil` to read the folder from its newest message.
    var position: Position?

    init(folder: Int, position: Position?) {
        self.folder = folder
        self.position = position
    }

    /// Throws `ProviderError.rejected` for a token this client didn't write.
    init(_ rawValue: String) throws {
        guard let token = try? JSONDecoder().decode(Self.self, from: Data(rawValue.utf8)) else {
            throw ProviderError.rejected
        }
        self = token
    }

    var rawValue: String {
        String(decoding: (try? JSONEncoder().encode(self)) ?? Data(), as: UTF8.self)
    }
}
