import MailCore
import MailUI
import OSLog
import UIKit

#if canImport(MailIntents)
    import MailIntents
    import WidgetKit
#endif

/// The app's launch. The mail database opens off the main thread, and everything that works on the mail starts once
/// it has. What iOS needs registered before launch finishes (background refresh, answers to alerts, intents) is
/// registered at once and waits for it. A database that can't open, as when it is damaged or the disk is full, leaves
/// the app showing why in every window instead of crashing at each launch.
final class AppLaunch {
    private enum State {
        /// Opening, with whoever is waiting for it.
        case opening([CheckedContinuation<AppServices, any Error>])
        case running(AppServices)
        case failed(any Error)
    }

    private var state = State.opening([])
    /// Where intents and tapped alerts send the app's windows, from launch on.
    let routes = IntentRoutes()
    private let log = Logger(subsystem: "com.idanbirman.goodmail", category: "launch")
    private lazy var alerts = AlertResponder { [unowned self] in try await services().push }
    /// The open. Kept so it has an owner; it ends by settling `state`, and nothing cancels it.
    private var opening: Task<Void, Never>?

    /// Call once, before launch finishes.
    func start() {
        _ = BackgroundDatabaseWork.shared
        #if DEBUG
            TestAnimations.startIfRequested()
        #endif
        switch PresenceTracker.shared.policy {
        case .suspends:
            BackgroundRefresh.register { [weak self] in try? await self?.services().syncScheduler.refresh }
        case .keepsRunning:
            // Nothing launches a Mac app in the background, and it syncs on its own while it runs.
            break
        }
        alerts.start()
        #if canImport(MailIntents)
            registerMailIntentsHost { [weak self] in
                guard let self else { throw CancellationError() }
                return try await services().intents
            }
        #endif
        opening = Task { [routes] in
            settle(await Result { try await AppServices.open(routes: routes) })
        }
    }

    /// The services, once the database has opened; its error if it couldn't.
    func services() async throws -> AppServices {
        switch state {
        case .running(let services): return services
        case .failed(let error): throw error
        case .opening(var waiting):
            // The open is quick and nothing cancels it, so a waiting caller isn't let go early when it is cancelled.
            return try await withCheckedThrowingContinuation { continuation in
                waiting.append(continuation)
                state = .opening(waiting)
            }
        }
    }

    /// The services if the database has opened, for callbacks that only come once it has.
    var running: AppServices? {
        guard case .running(let services) = state else { return nil }
        return services
    }

    /// The one place `state` leaves `opening`.
    private func settle(_ result: Result<AppServices, any Error>) {
        guard case .opening(let waiting) = state else { return }
        switch result {
        case .success(let services):
            state = .running(services)
            services.start()
        case .failure(let error):
            log.fault("Couldn't open the mail database: \(error, privacy: .public)")
            state = .failed(error)
        }
        for continuation in waiting { continuation.resume(with: result) }
    }
}

/// Everything that works on the mail, made once the database has opened.
struct AppServices {
    let model: AppModel
    let syncScheduler: SyncScheduler
    let push: PushCoordinator
    let snoozeAlarms: SnoozeAlarms
    let wrist: WristHost
    let routes: IntentRoutes
    let quickActions: QuickActionMenu

    static func open(routes: IntentRoutes) async throws -> AppServices {
        let model = try await openModel()
        #if DEBUG
            await TestSharedAccounts.seedIfRequested()
        #endif
        // Before any window shows, so a new device opens on the accounts its reader's other devices offer.
        do {
            try await model.followSharedAccounts()
        } catch {
            Logger.sharing.error("Couldn't read the accounts other devices share: \(error, privacy: .public)")
        }
        // Then the settings, so a new device opens with the reader's choices for the accounts it now has.
        await model.syncSettings()
        return AppServices(
            model: model, syncScheduler: SyncScheduler(model: model, presence: .shared),
            push: PushCoordinator(model: model, routes: routes, presence: .shared),
            snoozeAlarms: SnoozeAlarms(model: model),
            wrist: WristHost(model: model), routes: routes, quickActions: QuickActionMenu(model: model))
    }

    #if canImport(MailIntents)
        var intents: IntentsHost {
            IntentsHost(
                database: model.database, commands: model.commands, routes: routes,
                unsubscriber: model.listUnsubscriber, providers: model.providers,
                syncAll: { [model] in try await model.syncAll() },
                loadThread: { [model] in _ = try await model.messagesToAnswer(in: $0) })
        }
    #endif

    private static func openModel() async throws -> AppModel {
        #if DEBUG
            // `-GoodmailFailLaunch YES` shows what a database that can't open looks like.
            if UserDefaults.standard.bool(forKey: "GoodmailFailLaunch") { throw CocoaError(.fileReadCorruptFile) }
            if let count = SyntheticMailbox.requestedCount {
                return try SyntheticMailbox.makeModel(threadCount: count)
            }
        #endif
        return try await AppModel.openShared()
    }

    fileprivate func start() {
        syncScheduler.start()
        push.start(UIApplication.shared)
        snoozeAlarms.start()
        wrist.start()
        model.senderRules.start()
        #if canImport(MailIntents)
            let spotlight = SpotlightIndexer(host: intents)
            model.didChange = { change in
                await spotlight.follow(change)
                WidgetCenter.shared.reloadAllTimelines()
            }
        #endif
        #if DEBUG
            TestDelivery.scheduleIfRequested(model: model)
            TestAlert.scheduleIfRequested(model: model)
            TestArrival.scheduleIfRequested(routes: routes)
            SyntheticMailbox.deliverArrivalsIfRequested(to: model.database)
            TestMailTools.runIfRequested(model: model)
        #endif
    }
}
