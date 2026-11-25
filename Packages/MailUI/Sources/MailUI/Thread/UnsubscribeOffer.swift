public import Foundation
public import MailCore
public import Observation

/// The way off the mailing list a conversation came from, and how far the reader has got leaving it. Progress
/// changes only in `unsubscribe(_:)`, its answer and `finished(_:)`; which list is offered follows the messages.
@Observable
public final class UnsubscribeOffer {
    /// Where leaving the list stands, as the banner shows it.
    public enum State: Equatable, Sendable {
        /// The reader can leave.
        case offered
        case unsubscribing
        /// The list has the request, now or on an earlier visit.
        case unsubscribed
        /// The list's page opened for the reader to finish there. Remembered only once they say they did
        /// (`finished(_:)`), so leaving without finishing offers the list again next time.
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

    /// How far leaving one list has got, past `.offered`. The request is owned here: a newer ask waits for it, and the
    /// offer going with its reader cancels it.
    private enum Progress {
        case notAsked
        case unsubscribing(list: Contact, request: Task<Void, Never>)
        case answered(list: Contact, Answer)
    }

    /// What became of a request to leave.
    private enum Answer {
        case unsubscribed
        case pageOpened
        case failed

        var state: State {
            switch self {
            case .unsubscribed: .unsubscribed
            case .pageOpened: .pageOpened
            case .failed: .failed
            }
        }
    }

    private var progress = Progress.notAsked
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

    isolated deinit {
        if case .unsubscribing(_, let request) = progress { request.cancel() }
    }

    /// The list of the newest message that names one and isn't the reader's own, or `nil` for none.
    public func offer(in messages: [Message]) -> Offer? {
        guard
            let message = messages.last(where: {
                $0.unsubscribe != nil && $0.from.address.caseInsensitiveCompare(accountEmail) != .orderedSame
            }),
            let unsubscribe = message.unsubscribe
        else { return nil }
        return Offer(list: message.from, unsubscribe: unsubscribe, state: state(of: message.from))
    }

    /// Where leaving `list` stands now: its progress here, or whether an earlier visit left it.
    private func state(of list: Contact) -> State {
        switch progress {
        case .unsubscribing(let asked, _) where asked == list: .unsubscribing
        case .answered(let asked, let answer) where asked == list: answer.state
        case .notAsked, .unsubscribing, .answered:
            memory.contains(list.address, account: account) ? .unsubscribed : .offered
        }
    }

    /// Asks to leave the offered list, while it stands at `.offered` or `.failed`; asking again while a request is out
    /// does nothing. A page to finish on opens, and counts as asked.
    public func unsubscribe(_ offer: Offer) {
        if case .unsubscribing = progress { return }
        guard [.offered, .failed].contains(state(of: offer.list)) else { return }
        let request = Task { [weak self, perform] in
            let outcome: Result<ListUnsubscriber.Outcome, any Error>
            do {
                outcome = .success(try await perform(offer.unsubscribe))
            } catch {
                outcome = .failure(error)
            }
            self?.answered(outcome)
        }
        progress = .unsubscribing(list: offer.list, request: request)
    }

    /// Returns once the request out, if any, is answered.
    func settled() async {
        if case .unsubscribing(_, let request) = progress { await request.value }
    }

    /// The one place a request's answer lands.
    private func answered(_ outcome: Result<ListUnsubscriber.Outcome, any Error>) {
        guard case .unsubscribing(let list, _) = progress else { return }
        switch outcome {
        case .success(.done):
            memory.insert(list.address, account: account)
            progress = .answered(list: list, .unsubscribed)
        case .success(.openPage(let url)):
            // Opening the page is only the start: the list keeps sending until the reader finishes there.
            openURL(url)
            progress = .answered(list: list, .pageOpened)
        case .failure(let error) where error is CancellationError:
            progress = .notAsked
        case .failure:
            progress = .answered(list: list, .failed)
        }
    }

    /// The reader says they finished on the list's page, from `.pageOpened` only: the list is remembered as left.
    public func finished(_ offer: Offer) {
        guard state(of: offer.list) == .pageOpened else { return }
        memory.insert(offer.list.address, account: account)
        progress = .answered(list: offer.list, .unsubscribed)
    }
}
