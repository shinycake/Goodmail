public import Foundation
public import MailCore
public import Observation

/// The way off the mailing list a conversation came from, and how far the reader has got leaving it. Progress
/// changes only in `unsubscribe(_:)`; which list is offered follows the messages.
@Observable
public final class UnsubscribeOffer {
    /// Where leaving the list stands, as the banner shows it.
    public enum State: Equatable, Sendable {
        /// The reader can leave.
        case offered
        case unsubscribing
        /// The list has the request, now or on an earlier visit.
        case unsubscribed
        /// The list's page opened for the reader to finish there.
        case pageOpened
        /// The request didn't go through; the reader can try again.
        case failed
    }

    /// One list to leave: who sends it, how to leave it, and how far leaving has got.
    public struct Offer: Equatable, Sendable {
        public let list: Contact
        public let unsubscribe: Unsubscribe
        public let state: State
    }

    /// Progress past `.offered` for the list being left; `nil` until the reader asks.
    private var progress: (list: Contact, state: State)?
    @ObservationIgnored private let account: AccountID
    @ObservationIgnored private let accountEmail: String
    @ObservationIgnored private let perform: (Unsubscribe) async throws -> ListUnsubscriber.Outcome
    @ObservationIgnored private let openURL: (URL) -> Void
    @ObservationIgnored private let memory: UnsubscribedLists

    public init(
        account: AccountID,
        accountEmail: String,
        perform: @escaping (Unsubscribe) async throws -> ListUnsubscriber.Outcome,
        openURL: @escaping (URL) -> Void,
        memory: UnsubscribedLists = UnsubscribedLists()
    ) {
        self.account = account
        self.accountEmail = accountEmail
        self.perform = perform
        self.openURL = openURL
        self.memory = memory
    }

    /// The list of the newest message that names one and isn't the reader's own, or `nil` for none.
    public func offer(in messages: [Message]) -> Offer? {
        guard
            let message = messages.last(where: {
                $0.unsubscribe != nil && $0.from.address.caseInsensitiveCompare(accountEmail) != .orderedSame
            }),
            let unsubscribe = message.unsubscribe
        else { return nil }
        let list = message.from
        let state: State =
            if let progress, progress.list == list {
                progress.state
            } else if memory.contains(list.address, account: account) {
                .unsubscribed
            } else {
                .offered
            }
        return Offer(list: list, unsubscribe: unsubscribe, state: state)
    }

    /// Leaves the offered list, from `.offered` or `.failed`. A page to finish on opens, and counts as asked.
    public func unsubscribe(_ offer: Offer) async {
        guard [.offered, .failed].contains(offer.state) else { return }
        progress = (offer.list, .unsubscribing)
        let state: State
        do {
            switch try await perform(offer.unsubscribe) {
            case .done:
                state = .unsubscribed
            case .openPage(let url):
                openURL(url)
                state = .pageOpened
            }
            memory.insert(offer.list.address, account: account)
        } catch is CancellationError {
            progress = nil
            return
        } catch {
            state = .failed
        }
        progress = (offer.list, state)
    }
}
