import MailCore

/// The files one message carries, held under what Gmail accepts (`ComposeViewModel.attachmentLimit`), however they
/// come: picked, dropped, pasted or shared.
extension Array where Element == DraftAttachment {
    /// How many more bytes of files the message can take.
    var room: Int {
        ComposeViewModel.attachmentLimit - reduce(0) { $0 + $1.size }
    }

    /// Adds the file unless it would take the message past the limit. Returns whether it was added.
    mutating func attachIfRoom(_ file: DraftAttachment) -> Bool {
        guard file.size <= room else { return false }
        append(file)
        return true
    }
}
