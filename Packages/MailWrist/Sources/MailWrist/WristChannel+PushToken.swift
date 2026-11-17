#if canImport(WatchConnectivity)
    #if os(watchOS)
        public import Foundation
        import MailCore
    #else
        import Foundation
    #endif
    import WatchConnectivity

    /// How the watch's APNs token reaches the iPhone, which registers it with the relay beside its own (ADR-023). The
    /// watch never registers itself: the relay alerts it only when the iPhone doesn't confirm an alert in time.
    extension WristChannel {
        static let pushTokenKey = "pushToken"

        #if os(watchOS)
            /// For the watch: makes `token` the one the iPhone registers. It goes as the watch's application context,
            /// which the system keeps and delivers once, latest wins, even while the iPhone app isn't running.
            public func send(pushToken token: Data) {
                let session = WCSession.default
                guard session.activationState == .activated else { return }
                do {
                    try session.updateApplicationContext([Self.pushTokenKey: token.lowercaseHex])
                } catch {
                    Self.log.error("Couldn't send the watch's push token: \(error, privacy: .public)")
                }
            }
        #endif

        #if os(iOS)
            /// The watch token the iPhone should register now: the one the watch app sent, or `nil` when there is no
            /// paired watch with the app installed to alert.
            static func pushToken(of session: WCSession) -> WristSessionEvent {
                guard session.isPaired, session.isWatchAppInstalled,
                    let token = session.receivedApplicationContext[pushTokenKey] as? String
                else { return .watchPushToken(nil) }
                return .watchPushToken(token)
            }
        #endif
    }
#endif
