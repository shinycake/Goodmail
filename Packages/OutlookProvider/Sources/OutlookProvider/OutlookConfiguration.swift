import Foundation
import MailCore

extension OAuthClient {
    /// Goodmail's Microsoft Entra app: a public client with no secret, open to work, school and personal Microsoft
    /// accounts, so it signs in through the `common` endpoints.
    public static let outlook = OAuthClient(
        name: "outlook",
        authorizationEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/authorize")!,
        tokenEndpoint: URL(string: "https://login.microsoftonline.com/common/oauth2/v2.0/token")!,
        clientID: "aedf9c24-b8ba-4a4e-bb1a-cc594dec2bab",
        redirectURI: URL(string: "msauth.com.idanbirman.goodmail://auth")!,
        scopes: [
            "Mail.ReadWrite", "Mail.Send", "Contacts.Read", "People.Read", "User.Read",
            "offline_access", "openid", "email", "profile",
        ],
        // Microsoft wants the scopes again on every refresh.
        refreshesWithScopes: true
    )
}
