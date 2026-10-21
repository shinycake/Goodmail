import Foundation

/// The Google Cloud OAuth client and endpoints (see docs/setup/google-cloud.md). The iOS client has no secret.
public enum GmailConfiguration {
    public static let clientID = "847337870740-fpj7hd07nfsueispeug4nell21pf3vi2.apps.googleusercontent.com"
    public static let redirectURI = URL(
        string: "com.googleusercontent.apps.847337870740-fpj7hd07nfsueispeug4nell21pf3vi2:/oauthredirect"
    )!
    public static let redirectScheme = "com.googleusercontent.apps.847337870740-fpj7hd07nfsueispeug4nell21pf3vi2"
    public static let apiBaseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/")!
    public static let scopes = [
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/gmail.settings.basic",
        "https://www.googleapis.com/auth/contacts.readonly",
        "https://www.googleapis.com/auth/contacts.other.readonly",
        "openid",
        "email",
    ]
}
