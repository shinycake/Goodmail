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
    /// Quick Look for the selected attachment.
    case fileAttachment
    case fileExport
    case fileClose
    case editFind
    /// Attach Files and Add Link, while writing.
    case editInsert
    case viewLayout
    case viewZoom
    case viewCategories
    /// Turn Filter On or Off.
    case viewFilter
    /// The Filter by submenu: Unread, Starred and With Attachments.
    case viewFilterBy
    case viewComposer
    case mailboxFetch
    /// The Go To submenu: the sidebar's first nine rows.
    case mailboxGoTo
    /// The Move To submenu: the sidebar's first nine rows.
    case mailboxMoveTo
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
        case .fileNew, .fileAttachment, .fileExport, .fileClose: .file
        case .editFind, .editInsert: .edit
        case .viewLayout, .viewZoom, .viewCategories, .viewFilter, .viewFilterBy, .viewComposer: .view
        case .mailboxFetch, .mailboxGoTo, .mailboxMoveTo, .mailboxErase: .mailbox
        case .messageSend, .messageAnswer, .messageAway, .messageOrganize, .messageMark, .messageNavigate: .message
        case .formatStyle, .formatLists, .formatQuote: .format
        }
    }

    /// The submenu the section is, which the menu bar shows under a title of its own, or `nil` for a section of
    /// items set apart by a line.
    public var submenu: MenuSubmenu? {
        switch self {
        case .viewFilterBy: .filterBy
        case .mailboxGoTo: .goTo
        case .mailboxMoveTo: .moveTo
        default: nil
        }
    }
}

/// A submenu of the menu bar that holds a section of the app's commands.
public enum MenuSubmenu: Sendable {
    case filterBy
    case goTo
    case moveTo
}
