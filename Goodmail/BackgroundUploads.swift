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
    private struct State {
        /// Each task's answer so far, by task identifier.
        var replies: [Int: Data] = [:]
        /// Outcomes being passed to `onFinish`.
        var takingIn: [UploadID: Task<Void, Never>] = [:]
        /// What iOS asked to be called once the events it delivered have been taken in.
        var eventsCompletion: (@MainActor () -> Void)?
    }

    private let onFinish: @Sendable (UploadTicket, UploadOutcome) async -> Void
    private let state = Mutex(State())

    init(onFinish: @escaping @Sendable (UploadTicket, UploadOutcome) async -> Void) {
        self.onFinish = onFinish
    }

    var takingIn: Set<UploadID> { state.withLock { Set($0.takingIn.keys) } }

    func whenEventsAreTakenIn(_ completion: @escaping @MainActor () -> Void) {
        state.withLock { $0.eventsCompletion = completion }
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
                _ = self.state.withLock { $0.takingIn.removeValue(forKey: ticket.id) }
            }
        }
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let work = state.withLock { Array($0.takingIn.values) }
        Task {
            for task in work { await task.value }
            let completion = state.withLock { state in
                defer { state.eventsCompletion = nil }
                return state.eventsCompletion
            }
            // UIKit's completion handler is called once, on the main actor its type requires.
            await completion?()
        }
    }
}
