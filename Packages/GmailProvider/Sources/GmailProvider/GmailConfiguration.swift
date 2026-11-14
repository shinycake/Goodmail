import Foundation
import MailCore

/// The Gmail endpoints the provider calls (see docs/setup/google-cloud.md for the OAuth client).
public enum GmailConfiguration {
    public static let apiBaseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/")!
    /// Where requests carrying a whole message go, for messages too large to send as JSON.
    public static let uploadBaseURL = URL(string: "https://gmail.googleapis.com/upload/gmail/v1/")!
    /// Google's People API, for the address book.
    public static let peopleBaseURL = URL(string: "https://people.googleapis.com/v1/")!
    /// The Pub/Sub topic Gmail publishes changes to; its push subscription calls the relay (PushWorker/README.md).
    public static let pushTopic = "projects/goodmail-ios/topics/gmail-push"
    /// The full mail scope, not `gmail.modify`, because only it allows deleting mail for good (ADR-019).
    public static let fullMailScope = "https://mail.google.com/"
}

extension OAuthClient {
    /// The Google Cloud project's iOS OAuth client, which has no secret.
    public static let gmail = OAuthClient(
        name: "gmail",
        authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
        tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
        clientID: "847337870740-fpj7hd07nfsueispeug4nell21pf3vi2.apps.googleusercontent.com",
        redirectURI: URL(
            string: "com.googleusercontent.apps.847337870740-fpj7hd07nfsueispeug4nell21pf3vi2:/oauthredirect")!,
        scopes: [
            GmailConfiguration.fullMailScope,
            "https://www.googleapis.com/auth/gmail.settings.basic",
            "https://www.googleapis.com/auth/contacts.readonly",
            "https://www.googleapis.com/auth/contacts.other.readonly",
            "openid",
            "email",
        ],
        refreshesWithScopes: false
    )
}
