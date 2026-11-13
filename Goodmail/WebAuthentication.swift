import AuthenticationServices
import UIKit

/// Presents a sign-in page over a window and returns the redirect it ends on.
final class WebAuthentication: NSObject, ASWebAuthenticationPresentationContextProviding {
    private let window: UIWindow
    private var session: ASWebAuthenticationSession?

    init(window: UIWindow) {
        self.window = window
    }

    /// The redirect URL, or `nil` if the user closed the page.
    func authenticate(url: URL, callbackScheme: String) async throws -> URL? {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            // `@Sendable`, so it isn't inferred main-actor: the session doesn't promise which queue calls it.
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(callbackScheme)) {
                @Sendable url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(returning: nil)
                } else {
                    continuation.resume(throwing: error ?? URLError(.unknown))
                }
            }
            session.presentationContextProvider = self
            // No shared cookies: each sign-in starts clean, and iOS skips its "wants to use google.com" prompt.
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            session.start()
        }
    }

    /// The protocol is main-actor isolated, like this class.
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        window
    }
}
