/// Everything the reader can ask of the app by name: one table for the menu bar, the keyboard and, as they come, the
/// toolbar and a row's context menu (ADR-034). Each command says where the menu bar lists it, which keys reach it, and
/// whether the toolbar may show it; the screens on show say what it does now. Keys are Apple Mail's wherever Mail has
/// the command. The order of the cases is the order within each menu section.
public enum MailCommand: String, CaseIterable, Sendable {
    case settings

    case newMessage
    case newWindow
    case openInNewWindow
    case exportPDF
    case print
    case closeWindow

    case search
    case attachFiles
    case addLink

    case switchLayout
    case showPrimary
    case showPromotions
    case showSocial
    case showUpdates
    case showForums
    case showCopyFields

    case getMail
    case eraseTrash

    case send
    case sendLater
    case reply
    case replyAll
    case forward
    case forwardAsAttachment
    case editAsNew
    case archive
    case trash
    case reportSpam
    case move
    case changeLabels
    case snooze
    /// Mark as Read or Mark as Unread, whichever the conversation needs.
    case markRead
    /// Star or Unstar.
    case star
    /// Pin or Unpin.
    case pin
    /// Mute or Unmute.
    case mute
    case previousThread
    case nextThread

    case strikethrough
    case bulletedList
    case numberedList
    case increaseQuoteLevel
    case decreaseQuoteLevel

    public var place: MenuPlace {
        switch self {
        case .settings: .settings
        case .newMessage, .newWindow, .openInNewWindow: .fileNew
        case .exportPDF, .print: .fileExport
        case .closeWindow: .fileClose
        case .search: .editFind
        case .attachFiles, .addLink: .editInsert
        case .switchLayout: .viewLayout
        case .showPrimary, .showPromotions, .showSocial, .showUpdates, .showForums: .viewCategories
        case .showCopyFields: .viewComposer
        case .getMail: .mailboxFetch
        case .eraseTrash: .mailboxErase
        case .send, .sendLater: .messageSend
        case .reply, .replyAll, .forward, .forwardAsAttachment, .editAsNew: .messageAnswer
        case .archive, .trash, .reportSpam: .messageAway
        case .move, .changeLabels, .snooze: .messageOrganize
        case .markRead, .star, .pin, .mute: .messageMark
        case .previousThread, .nextThread: .messageNavigate
        case .strikethrough: .formatStyle
        case .bulletedList, .numberedList: .formatLists
        case .increaseQuoteLevel, .decreaseQuoteLevel: .formatQuote
        }
    }

    public var keys: CommandKeys {
        switch self {
        case .settings: .own(KeyChord(.command, ","))
        case .newMessage: .own(KeyChord(.command, "n"))
        case .newWindow: .system(.newWindow)
        case .openInNewWindow: .own(KeyChord(.command, "o"))
        case .print: .system(.print)
        case .closeWindow: .system(.close)
        case .search: .system(.findAndReplace)
        case .attachFiles: .own(KeyChord([.command, .shift], "a"))
        case .addLink: .own(KeyChord(.command, "k"))
        // Goodmail's own: Mail has no chat layout.
        case .switchLayout: .own(KeyChord([.command, .shift], "k"))
        case .showCopyFields: .own(KeyChord([.command, .option], "b"))
        case .getMail: .own(KeyChord([.command, .shift], "n"))
        case .eraseTrash: .own(KeyChord([.command, .shift], .delete))
        case .send: .own(KeyChord([.command, .shift], "d"))
        case .reply: .own(KeyChord(.command, "r"))
        case .replyAll: .own(KeyChord([.command, .shift], "r"))
        case .forward: .own(KeyChord([.command, .shift], "f"))
        case .archive: .own(KeyChord([.command, .control], "a"))
        case .trash: .own(KeyChord(.command, .delete))
        case .reportSpam: .own(KeyChord([.command, .shift], "j"))
        // Goodmail's own: Mail's Move to has no keys.
        case .move: .own(KeyChord([.command, .shift], "m"))
        // Goodmail's own: Mail has no snooze.
        case .snooze: .own(KeyChord([.command, .shift], "s"))
        case .markRead: .own(KeyChord([.command, .shift], "u"))
        case .star: .own(KeyChord([.command, .shift], "l"))
        case .previousThread: .own(KeyChord([.command, .control], .upArrow))
        case .nextThread: .own(KeyChord([.command, .control], .downArrow))
        case .increaseQuoteLevel: .own(KeyChord(.command, "'"))
        case .decreaseQuoteLevel: .own(KeyChord([.command, .option], "'"))
        case .exportPDF, .showPrimary, .showPromotions, .showSocial, .showUpdates, .showForums, .sendLater,
            .forwardAsAttachment, .editAsNew, .changeLabels, .pin, .mute, .strikethrough, .bulletedList,
            .numberedList:
            .none
        }
    }

    /// Whether the reader may put the command in a window's toolbar.
    public var mayShowInToolbar: Bool {
        switch self {
        case .newMessage, .getMail, .search, .print, .attachFiles, .switchLayout, .send, .reply, .replyAll, .forward,
            .archive, .trash, .reportSpam, .move, .changeLabels, .snooze, .markRead, .star, .pin, .mute:
            true
        case .settings, .newWindow, .openInNewWindow, .exportPDF, .closeWindow, .addLink, .showPrimary,
            .showPromotions, .showSocial, .showUpdates, .showForums, .showCopyFields, .eraseTrash, .sendLater,
            .forwardAsAttachment, .editAsNew, .previousThread, .nextThread, .strikethrough, .bulletedList,
            .numberedList, .increaseQuoteLevel, .decreaseQuoteLevel:
            false
        }
    }

    /// The answer the command opens the composer with, for the commands that answer a message.
    public var answer: Answer? {
        switch self {
        case .reply: .reply
        case .replyAll: .replyAll
        case .forward: .forward
        case .forwardAsAttachment: .forwardAsAttachment
        case .editAsNew: .editAsNew
        default: nil
        }
    }

    /// The Inbox category the command shows, for the View menu's categories.
    public var category: InboxCategory? {
        switch self {
        case .showPrimary: .primary
        case .showPromotions: .promotions
        case .showSocial: .social
        case .showUpdates: .updates
        case .showForums: .forums
        default: nil
        }
    }
}
