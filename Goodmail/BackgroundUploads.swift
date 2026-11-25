import Foundation
import MailCore
import Synchronization

/// The background `URLSession` that sends go through, so a send carries on while the app is suspended or after
/// it is gone. Made at launch: iOS then hands over the outcomes of uploads that finished while the app was away,
/// and each goes to `onFinish`.
nonisolated final class BackgroundUploads: UploadTransport {
    static let identifier = "com.idanbirman.goodmail.uploads"

    private let delegate: Delegate
    private let session: URLSession

    init(onFinish: @escaping @Sendable (UploadTicket, UploadOutcome) async -> Void) {
        delegate = Delegate(onFinish: onFinish)
        let configuration = URLSessionConfiguration.background(withIdentifier: Self.identifier)
        // Relaunch the app to hear an outcome, and start at once rather than when iOS finds it convenient.
        configuration.sessionSendsLaunchEvents = true
        configuration.isDiscretionary = false
        session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    }

    func upload(_ request: URLRequest, from file: URL, ticket: UploadTicket) async throws {
        let task = session.uploadTask(with: request, fromFile: file)
        task.taskDescription = ticket.description
        task.resume()
    }

    /// The session's uploads, and those whose outcome is still being taken in, so none is mistaken for lost.
    func activeUploads() async -> Set<UploadID> {
        let tasks = await session.allTasks.compactMap { $0.taskDescription.flatMap(UploadTicket.init)?.id }
        return Set(tasks).union(delegate.takingIn)
    }

    /// iOS launched or woke the app for this session's events; `completion` tells it they have been taken in.
    func handleEvents(completion: @escaping @MainActor () -> Void) {
        delegate.whenEventsAreTakenIn(completion)
    }
}

private nonisolated final class Delegate: NSObject, URLSessionDataDelegate, Sendable {
    typealias Handler = @MainActor () -> Void

    private struct State {
        /// Each task's answer so far, by task identifier.
        var replies: [Int: Data] = [:]
        /// Outcomes being passed to `onFinish`.
        var takingIn: [UploadID: Task<Void, Never>] = [:]
        /// What iOS asked to be called once the events it delivered have been taken in, and when that is.
        var events = BackgroundEvents<Handler>()

        /// The handlers whose events are now delivered and taken in.
        mutating func due() -> [Handler] {
            events.due(allTakenIn: takingIn.isEmpty)
        }
    }

    private let onFinish: @Sendable (UploadTicket, UploadOutcome) async -> Void
    private let state = Mutex(State())

    init(onFinish: @escaping @Sendable (UploadTicket, UploadOutcome) async -> Void) {
        self.onFinish = onFinish
    }

    var takingIn: Set<UploadID> { state.withLock { Set($0.takingIn.keys) } }

    /// The launch can get this before or after iOS says it delivered every event; either way `completion` is called
    /// once they're taken in.
    func whenEventsAreTakenIn(_ completion: @escaping Handler) {
        call(
            state.withLock { state in
                state.events.receive(completion)
                return state.due()
            })
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        state.withLock { $0.replies[dataTask.taskIdentifier, default: Data()].append(data) }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let body = state.withLock { $0.replies.removeValue(forKey: task.taskIdentifier) } ?? Data()
        guard let ticket = task.taskDescription.flatMap(UploadTicket.init) else { return }
        let outcome: UploadOutcome =
            if error == nil, let response = task.response as? HTTPURLResponse {
                .response(status: response.statusCode, body: body)
            } else {
                .noResponse
            }
        state.withLock { state in
            state.takingIn[ticket.id] = Task { [onFinish] in
                await onFinish(ticket, outcome)
                call(
                    self.state.withLock { state in
                        state.takingIn[ticket.id] = nil
                        return state.due()
                    })
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        call(
            state.withLock { state in
                state.events.delivered()
                return state.due()
            })
    }

    /// Calls UIKit's completion handlers, each once, on the main actor their type requires. The task only hops
    /// there: the handlers return at once, can't fail and mustn't be skipped, so nothing waits on it or cancels it.
    private func call(_ handlers: [Handler]) {
        guard !handlers.isEmpty else { return }
        Task { @MainActor in
            for handler in handlers { handler() }
        }
    }
}
