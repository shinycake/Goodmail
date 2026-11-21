/// The filter a window puts on its list: off, or on with the facts every conversation shown must have. It sits on a
/// built-in `MailCondition`, so the list asks the same question Shortcuts and rules do. A window keeps one
/// (`WindowState.filter`), and it stays when the reader moves to another mailbox, as the Inbox category does.
public enum ListFilter: Equatable, Codable, Sendable {
    /// What a conversation can be asked for. Several chosen at once all have to hold.
    public enum Option: String, CaseIterable, Codable, Sendable {
        case unread
        case starred
        case withAttachments

        var flag: MailFlag {
            switch self {
            case .unread: .unread
            case .starred: .starred
            case .withAttachments: .hasAttachments
            }
        }
    }

    /// Not filtering. `last` is what the filter asked for when it went off, so turning it on again brings it back.
    case off(last: Set<Option>)
    /// Filtering by `choices`, never empty: taking the last one away turns the filter off.
    case on(Set<Option>)

    /// What a window starts with, and what turning the filter on asks for when nothing was chosen before.
    public static let none = ListFilter.off(last: [])
    private static let firstChoice: Set<Option> = [.unread]

    /// What the list has to be, or `nil` while the filter is off.
    public var choices: Set<Option>? {
        if case .on(let choices) = self { choices } else { nil }
    }

    public var isOn: Bool { choices != nil }

    /// The condition a conversation has to meet, or `nil` while the filter is off.
    public var condition: MailCondition? {
        choices.map { choices in
            .all(Option.allCases.filter(choices.contains).map { .flag($0.flag, true) })
        }
    }

    /// Whether the list shows `mail`: always while the filter is off.
    public func admits(_ mail: MailFacts) -> Bool {
        condition?.matches(mail) ?? true
    }

    /// The filter after Turn Filter On or Off.
    public func toggled() -> ListFilter {
        switch self {
        case .on(let choices): .off(last: choices)
        case .off(let last): .on(last.isEmpty ? Self.firstChoice : last)
        }
    }

    /// The filter after the reader checks or unchecks `option` in the Filter by menu. Checking one while the filter
    /// is off turns it on for that one alone.
    public func toggling(_ option: Option) -> ListFilter {
        switch self {
        case .off:
            return .on([option])
        case .on(var choices):
            if choices.remove(option) == nil { choices.insert(option) }
            return choices.isEmpty ? .off(last: [option]) : .on(choices)
        }
    }

    /// Whether `option` is checked in the Filter by menu.
    public func asks(for option: Option) -> Bool {
        choices?.contains(option) == true
    }
}
