import Foundation

/// How mailbox rows look: how many lines of each thread's preview they show, and whether the sender's monogram
/// leads each row. Without it, the account's badge stays, on its own.
public struct RowDisplay: Equatable, Sendable {
    /// The preview lengths offered, in lines; zero shows none.
    public static let previewLineChoices = [0, 1, 2, 3]
    public static let standard = RowDisplay(previewLines: 2, showsAvatars: true)

    public var previewLines: Int
    public var showsAvatars: Bool

    public init(previewLines: Int, showsAvatars: Bool) {
        self.previewLines = previewLines
        self.showsAvatars = showsAvatars
    }

    /// "None", or the preview's length in lines.
    static func previewTitle(_ lines: Int) -> String {
        guard lines > 0 else {
            return String(
                localized: "Preview: None", defaultValue: "None", bundle: .module,
                comment: "Mailbox rows show no preview")
        }
        return String(
            localized: "\(lines) lines", bundle: .module, comment: "Mailbox rows show this many lines of preview")
    }
}
