/// A menu of the menu bar that holds the app's commands.
public enum MenuBarMenu: Hashable, Sendable {
    /// The app's own menu, named after it, which holds Settings.
    case application
    case file
    case edit
    case view
    case mailbox
    case message
    case format
}

/// A section of a menu in the menu bar, set apart from its neighbors by a line. The cases are in menu order, so the
/// menu bar lists each menu's sections, and their commands, as they are written here and in `MailCommand`.
public enum MenuPlace: CaseIterable, Sendable {
    case settings
    /// New Message, New Viewer Window, Open in New Window.
    case fileNew
    case fileExport
    case fileClose
    case editFind
    /// Attach Files and Add Link, while writing.
    case editInsert
    case viewLayout
    case viewCategories
    case viewComposer
    case mailboxFetch
    case mailboxErase
    case messageSend
    case messageAnswer
    case messageAway
    case messageOrganize
    case messageMark
    case messageNavigate
    case formatStyle
    case formatLists
    case formatQuote

    public var menu: MenuBarMenu {
        switch self {
        case .settings: .application
        case .fileNew, .fileExport, .fileClose: .file
        case .editFind, .editInsert: .edit
        case .viewLayout, .viewCategories, .viewComposer: .view
        case .mailboxFetch, .mailboxErase: .mailbox
        case .messageSend, .messageAnswer, .messageAway, .messageOrganize, .messageMark, .messageNavigate: .message
        case .formatStyle, .formatLists, .formatQuote: .format
        }
    }
}
