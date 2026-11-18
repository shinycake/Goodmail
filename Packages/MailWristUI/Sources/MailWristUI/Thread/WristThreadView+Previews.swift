#if DEBUG
    import Foundation
    import MailCore
    import MailWrist
    import SwiftUI

    /// A conversation of the sample's Gmail account, which the watch reads itself, and of its iCloud account, which
    /// only the iPhone can (ADR-023).
    private enum PreviewThread {
        static let sample = WristSnapshot.sample(.english)
        static let direct = sample.rows[0].id
        static let relayed = sample.rows[1].id

        @MainActor static func view(
            _ id: ThreadSummary.ID, own: (@Sendable (ThreadSummary.ID) async throws -> WristThreadReply)? = nil,
            patience: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(15)) }
        ) -> some View {
            let inbox = WristInboxModel()
            inbox.receive(.snapshot(sample))
            let threads = WristThreads(patience: patience, own: own)
            threads.direct = [direct.accountID]
            return NavigationStack { WristThreadView(id: id, threads: threads, inbox: inbox) }
        }
    }

    #Preview("Loading") {
        PreviewThread.view(
            PreviewThread.direct,
            own: { _ in
                try await Task.sleep(for: .seconds(3_600))
                throw CancellationError()
            })
    }

    #Preview("Direct, Try Again") {
        PreviewThread.view(PreviewThread.direct, own: { _ in throw URLError(.timedOut) })
    }

    #Preview("Relayed, Needs iPhone") {
        PreviewThread.view(PreviewThread.relayed, patience: {})
    }

    #Preview("Loaded") {
        let thread = WristThread.samples(for: PreviewThread.sample, .english)[0]
        PreviewThread.view(PreviewThread.direct, own: { _ in .thread(thread) })
    }
#endif
