import Foundation
import Synchronization

/// A send queue in memory, holding only what one process sends itself, as `ImmediateDelivery` does for the Share
/// extension. What the queue reads or records about the account and its drafts' saved copies still goes to `base`,
/// the shared database, so the app sees a saved copy the moment it is made.
final class PrivateQueue: OutgoingStore {
    private let base: any OutgoingStore
    private let held: Mutex<[OutgoingMessage]>

    init(holding messages: [OutgoingMessage], over base: any OutgoingStore) {
        self.base = base
        held = Mutex(messages)
    }

    /// Takes everything still in the queue, in whatever state it was left: what didn't go. The queue is empty from
    /// then on, so nothing more is attempted, and no step of an attempt under way can change what was taken.
    func takeAll() -> [OutgoingMessage] {
        held.withLock { held in
            defer { held = [] }
            return held
        }
    }

    func enqueue(_ message: OutgoingMessage) throws {
        held.withLock { held in
            held.removeAll { $0.id == message.id }
            held.append(message)
        }
    }

    func enqueueSave(_ message: OutgoingMessage) throws {
        held.withLock { held in
            guard let index = held.firstIndex(where: { $0.id == message.id }) else { return held.append(message) }
            guard held[index].purpose == message.purpose, held[index].delivery == .queued else { return }
            held[index].draft = message.draft
            held[index].sendAt = min(held[index].sendAt, message.sendAt)
        }
    }

    func finish(_ message: OutgoingMessage) throws -> Bool {
        held.withLock { held in
            guard let index = held.firstIndex(where: { $0.id == message.id }),
                held[index].draft == message.draft, held[index].delivery == .queued
            else { return false }
            held.remove(at: index)
            return true
        }
    }

    func savedCopy(of draft: Draft.ID) throws -> Message.ID? {
        try base.savedCopy(of: draft)
    }

    func setSavedCopy(_ copy: Message.ID?, of draft: Draft.ID) throws {
        try base.setSavedCopy(copy, of: draft)
    }

    func cancel(_ id: Draft.ID) throws -> OutgoingMessage? {
        held.withLock { held in
            guard let index = held.firstIndex(where: { $0.id == id && $0.delivery == .queued }) else { return nil }
            return held.remove(at: index)
        }
    }

    func requeue(_ id: Draft.ID, as purpose: OutgoingMessage.Purpose, at date: Date) throws -> OutgoingMessage? {
        held.withLock { held in
            guard let index = held.firstIndex(where: { $0.id == id && $0.delivery == .queued }) else { return nil }
            held[index].purpose = purpose
            held[index].sendAt = date
            return held[index]
        }
    }

    func dueMessages(for account: AccountID, by date: Date) throws -> [OutgoingMessage] {
        held.withLock { held in
            held.filter { $0.draft.accountID == account && $0.delivery == .queued && $0.sendAt <= date }
                .sorted { $0.sendAt < $1.sendAt }
        }
    }

    func uploadingMessages(for account: AccountID) throws -> [OutgoingMessage] {
        held.withLock { held in
            held.filter { message in
                guard message.draft.accountID == account, case .uploading = message.delivery else { return false }
                return true
            }
        }
    }

    func update(_ id: Draft.ID, from expected: OutgoingMessage.Delivery, to message: OutgoingMessage?) throws -> Bool {
        held.withLock { held in
            guard let index = held.firstIndex(where: { $0.id == id && $0.delivery == expected }) else { return false }
            if let message { held[index] = message } else { held.remove(at: index) }
            return true
        }
    }

    func remove(_ id: Draft.ID) throws {
        held.withLock { $0.removeAll { $0.id == id } }
    }

    func sender(for account: AccountID) throws -> Contact {
        try base.sender(for: account)
    }
}
