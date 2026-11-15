import Foundation
import MailCore

/// Where `changes(since:)` picks up: every folder's STATUS when the cursor was taken, keyed by wire name, and on a
/// server without CONDSTORE the read and starred flags of each folder's latest messages, to compare.
struct IMAPCursor: Codable, Equatable {
    var folders: [String: IMAPFolderStatus]
    /// By wire name, then UID. `nil` in a cursor from before these were kept, and on servers with CONDSTORE.
    var marks: [String: [UInt32: FlagMarks]]?

    init(folders: [String: IMAPFolderStatus], marks: [String: [UInt32: FlagMarks]] = [:]) {
        self.folders = folders
        self.marks = marks.isEmpty ? nil : marks
    }

    /// Throws `ProviderError.cursorExpired` for a cursor this client didn't write.
    init(_ rawValue: String) throws {
        guard let cursor = try? JSONDecoder().decode(Self.self, from: Data(rawValue.utf8)) else {
            throw ProviderError.cursorExpired
        }
        self = cursor
    }

    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Strings and integers always encode.
        return String(decoding: (try? encoder.encode(self)) ?? Data(), as: UTF8.self)
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
