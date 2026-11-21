import MailCore
import UIKit

extension SenderRules {
    /// The commands about senders and rules, in the order the Message menu and a context menu list them.
    static let commands: [MailCommand] = [.applyRules, .vipSender, .blockSender]

    /// What Apply Rules, the VIP command and Block Sender do to `threads`, from `sender` when they are all from one
    /// person other than the reader; `nil` for any other command. Without such a sender, the sender's commands are
    /// dimmed.
    func answer(to command: MailCommand, for threads: [ThreadSummary.ID], from sender: SenderAddress?)
        -> CommandAnswer?
    {
        switch command {
        case .applyRules:
            guard !threads.isEmpty else { return .unavailable }
            return .ready(perform: { [self] in applyRules(to: threads) })
        case .vipSender:
            guard let sender else { return .unavailable }
            let isVIP = !vips.contains(sender)
            return .ready(perform: { [self] in setVIP(sender, isVIP) }, title: Self.vipTitle(isVIP))
        case .blockSender:
            guard let sender else { return .unavailable }
            return .ready(perform: { [self] in block(sender, then: threads) })
        default:
            return nil
        }
    }

    /// The same commands as a section of a context menu, leaving out what the menu bar would dim.
    func menuSection(for threads: [ThreadSummary.ID], from sender: SenderAddress?) -> UIMenu {
        let actions = Self.commands.compactMap { command -> UIAction? in
            guard case .ready(let perform, let title, _) = answer(to: command, for: threads, from: sender) else {
                return nil
            }
            return UIAction(
                title: title ?? command.title, image: UIImage(systemName: command.senderSymbol),
                attributes: command == .blockSender ? .destructive : []
            ) { _ in perform() }
        }
        return UIMenu(options: .displayInline, children: actions)
    }

    static func vipTitle(_ isVIP: Bool) -> String {
        isVIP
            ? MailCommand.vipSender.title
            : String(
                localized: "Remove Sender from VIPs", table: "SenderRules", bundle: .module,
                comment: "Menu command that takes the sender of the picked mail off the reader's VIPs")
    }
}

extension MailCommand {
    /// The menu bar's names for the commands about senders and rules.
    var senderTitle: String {
        switch self {
        case .applyRules:
            String(localized: "Apply Rules", table: "SenderRules", bundle: .module, comment: "Menu bar command")
        case .vipSender:
            String(
                localized: "Add Sender to VIPs", table: "SenderRules", bundle: .module,
                comment: "Menu command that adds the sender of the picked mail to the reader's VIPs")
        case .blockSender:
            String(
                localized: "Block Sender", table: "SenderRules", bundle: .module,
                comment: "Menu command that writes a rule sending the sender's mail to Trash")
        default:
            title
        }
    }

    fileprivate var senderSymbol: String {
        switch self {
        case .vipSender: "crown"
        case .blockSender: "nosign"
        default: "wand.and.rays"
        }
    }
}

/// A screen that offers the sender's commands on a person's address or picture, as the reader's header and a chat's
/// avatars show them. Their menus find it up the responder chain when they open (`SenderMenu`).
@MainActor
protocol SenderMenuOffering: UIResponder {
    func senderMenu(for contact: Contact) -> UIMenu?
}

enum SenderMenu {
    /// The sender's commands for `contact`, from the first screen up `view`'s responder chain that offers them,
    /// asked each time the menu opens, so it says the VIP state then.
    static func deferred(for contact: Contact, from view: UIView) -> UIMenuElement {
        UIDeferredMenuElement.uncached { [weak view] completion in
            guard let view else { return completion([]) }
            let screen = sequence(first: view as UIResponder, next: \.next).lazy
                .compactMap { $0 as? any SenderMenuOffering }.first
            completion(screen?.senderMenu(for: contact).map { [$0] } ?? [])
        }
    }
}
