import Foundation
import MailCore

/// Where `changes(since:)` picks up: every folder's STATUS when the cursor was taken, keyed by wire name.
struct ICloudCursor: Codable, Equatable {
    var folders: [String: IMAPFolderStatus]

    init(folders: [String: IMAPFolderStatus]) {
        self.folders = folders
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
struct ICloudPageToken: Codable, Equatable {
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
