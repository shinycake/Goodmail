public import Foundation

/// The watch's copy of its mailbox, kept in a file so the Inbox and the changes the iPhone hasn't run yet survive a
/// relaunch with the iPhone away. The only reader and writer of that file.
public actor WristStore {
    private let file: URL

    /// Keeps the mailbox in `directory`, which it creates when needed.
    public init(directory: URL) {
        file = directory.appending(path: "wrist-mailbox.json")
    }

    /// The stored mailbox; an empty one when there is none yet, or it can't be read, as after a format change.
    public func load() -> WristMailbox {
        guard let data = try? Data(contentsOf: file),
            let mailbox = try? JSONDecoder().decode(WristMailbox.self, from: data)
        else { return WristMailbox() }
        return mailbox
    }

    public func save(_ mailbox: WristMailbox) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(mailbox).write(to: file, options: .atomic)
    }
}
