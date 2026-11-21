/// Everything the reader can ask of the app by name: one table for the menu bar, the keyboard and, as they come, the
/// toolbar and a row's context menu (ADR-034). Each command says where the menu bar lists it, which keys reach it, and
/// whether the toolbar may show it; the screens on show say what it does now. Keys are Apple Mail's wherever Mail has
/// the command. The order of the cases is the order within each menu section.
public enum MailCommand: String, CaseIterable, Sendable {
    case settings

    case newMessage
    case newWindow
    case openInNewWindow
    /// Quick Look for the attachment that is selected.
    case quickLook
    case exportPDF
    case print
    case closeWindow

    case search
    case findInConversation
    case findNext
    case findPrevious
    case attachFiles
    case addLink

    case switchLayout
    case zoomIn
    case zoomOut
    case actualSize
    case showPrimary
    case showPromotions
    case showSocial
    case showUpdates
    case showForums
    /// Turns the list's filter on, or off.
    case toggleFilter
    case filterByUnread
    case filterByStarred
    case filterByAttachments
    case showCopyFields

    case getMail
    /// New Label, as the sidebar's toolbar button has it: Mail's New Mailbox.
    case newLabel
    /// New Smart Mailbox, beside New Label as Mail has it beside New Mailbox.
    case newSmartMailbox
    /// Opens the sidebar's first nine rows, from ⌘1 to ⌘9.
    case goTo1, goTo2, goTo3, goTo4, goTo5, goTo6, goTo7, goTo8, goTo9
    /// Moves the picked conversations to the sidebar's first nine rows, from ⌃⌘1 to ⌃⌘9.
    case moveTo1, moveTo2, moveTo3, moveTo4, moveTo5, moveTo6, moveTo7, moveTo8, moveTo9
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
    /// Runs the rules on the conversations picked now (ADR-038).
    case applyRules
    /// Add Sender to VIPs, or Remove Sender from VIPs.
    case vipSender
    /// Writes a rule that sends the sender's mail to Trash.
    case blockSender
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
        case .quickLook: .fileAttachment
        case .exportPDF, .print: .fileExport
        case .closeWindow: .fileClose
        case .search, .findInConversation, .findNext, .findPrevious: .editFind
        case .attachFiles, .addLink: .editInsert
        case .switchLayout: .viewLayout
        case .zoomIn, .zoomOut, .actualSize: .viewZoom
        case .showPrimary, .showPromotions, .showSocial, .showUpdates, .showForums: .viewCategories
        case .toggleFilter: .viewFilter
        case .filterByUnread, .filterByStarred, .filterByAttachments: .viewFilterBy
        case .showCopyFields: .viewComposer
        case .getMail: .mailboxFetch
        case .newLabel, .newSmartMailbox: .mailboxNew
        case .goTo1, .goTo2, .goTo3, .goTo4, .goTo5, .goTo6, .goTo7, .goTo8, .goTo9: .mailboxGoTo
        case .moveTo1, .moveTo2, .moveTo3, .moveTo4, .moveTo5, .moveTo6, .moveTo7, .moveTo8, .moveTo9: .mailboxMoveTo
        case .eraseTrash: .mailboxErase
        case .send, .sendLater: .messageSend
        case .reply, .replyAll, .forward, .forwardAsAttachment, .editAsNew: .messageAnswer
        case .archive, .trash, .reportSpam: .messageAway
        case .move, .changeLabels, .snooze: .messageOrganize
        case .markRead, .star, .pin, .mute: .messageMark
        case .applyRules, .vipSender, .blockSender: .messageSender
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
        // The Finder's key for Quick Look.
        case .quickLook: .own(KeyChord(.command, "y"))
        case .print: .system(.print)
        case .closeWindow: .system(.close)
        case .search: .system(.findAndReplace)
        // Find, Find Next and Find Previous have Apple's keys, on the system's own items.
        case .findInConversation: .system(.find)
        case .findNext: .system(.findNext)
        case .findPrevious: .system(.findPrevious)
        case .attachFiles: .own(KeyChord([.command, .shift], "a"))
        case .addLink: .own(KeyChord(.command, "k"))
        // Goodmail's own: Mail has no chat layout.
        case .switchLayout: .own(KeyChord([.command, .shift], "k"))
        // Zoom In and Out ride on Format > Font's Bigger and Smaller, which hold ⌘+ and ⌘−; the reader answers them.
        case .zoomIn: .system(.biggerText)
        case .zoomOut: .system(.smallerText)
        case .actualSize: .own(KeyChord(.command, "0"))
        // Mail's Filter is ⌘L too, where Goodmail's Star takes ⇧⌘L.
        case .toggleFilter: .own(KeyChord(.command, "l"))
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
        case .applyRules: .own(KeyChord([.command, .option], "l"))
        case .previousThread: .own(KeyChord([.command, .control], .upArrow))
        case .nextThread: .own(KeyChord([.command, .control], .downArrow))
        case .increaseQuoteLevel: .own(KeyChord(.command, "'"))
        case .decreaseQuoteLevel: .own(KeyChord([.command, .option], "'"))
        case .filterByUnread, .filterByStarred, .filterByAttachments, .exportPDF, .newLabel, .showPrimary,
            .showPromotions,
            .showSocial, .showUpdates, .showForums, .sendLater,
            .forwardAsAttachment, .editAsNew, .changeLabels, .pin, .mute, .vipSender, .blockSender, .strikethrough,
            .bulletedList, .numberedList, .newSmartMailbox:
            .none
        case .goTo1, .goTo2, .goTo3, .goTo4, .goTo5, .goTo6, .goTo7, .goTo8, .goTo9, .moveTo1, .moveTo2, .moveTo3,
            .moveTo4, .moveTo5, .moveTo6, .moveTo7, .moveTo8, .moveTo9:
            // The keys follow the number.
            rowShortcut.map { .own($0.chord) } ?? .none
        }
    }

    /// Whether the reader may put the command in a window's toolbar.
    public var mayShowInToolbar: Bool {
        switch self {
        case .newMessage, .getMail, .search, .print, .attachFiles, .switchLayout, .send, .reply, .replyAll, .forward,
            .archive, .trash, .reportSpam, .move, .changeLabels, .snooze, .markRead, .star, .pin, .mute:
            true
        case .settings, .newWindow, .openInNewWindow, .quickLook, .findInConversation, .findNext, .findPrevious,
            .zoomIn, .zoomOut, .actualSize, .exportPDF, .closeWindow, .addLink, .showPrimary,
            .showPromotions, .showSocial, .showUpdates, .showForums, .showCopyFields, .newLabel, .newSmartMailbox,
            .eraseTrash,
            .sendLater,
            .forwardAsAttachment, .editAsNew, .applyRules, .vipSender, .blockSender, .previousThread, .nextThread,
            .strikethrough, .bulletedList,
            .numberedList, .increaseQuoteLevel, .decreaseQuoteLevel, .toggleFilter, .filterByUnread, .filterByStarred,
            .filterByAttachments, .goTo1, .goTo2, .goTo3, .goTo4, .goTo5, .goTo6, .goTo7, .goTo8, .goTo9, .moveTo1,
            .moveTo2, .moveTo3, .moveTo4, .moveTo5, .moveTo6, .moveTo7, .moveTo8, .moveTo9:
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

    /// The filter choice the command checks or unchecks, for the View menu's Filter by.
    public var filterOption: ListFilter.Option? {
        switch self {
        case .filterByUnread: .unread
        case .filterByStarred: .starred
        case .filterByAttachments: .withAttachments
        default: nil
        }
    }

    /// The sidebar row the command reaches by its number.
    public var rowShortcut: RowShortcut? {
        let goTo: [MailCommand] = [.goTo1, .goTo2, .goTo3, .goTo4, .goTo5, .goTo6, .goTo7, .goTo8, .goTo9]
        let moveTo: [MailCommand] = [
            .moveTo1, .moveTo2, .moveTo3, .moveTo4, .moveTo5, .moveTo6, .moveTo7, .moveTo8, .moveTo9,
        ]
        if let index = goTo.firstIndex(of: self) { return .goTo(index + 1) }
        return moveTo.firstIndex(of: self).map { .moveTo($0 + 1) }
    }
}
