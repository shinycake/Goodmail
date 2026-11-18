import Foundation
import GmailProvider
import MailCore
import MailStore
import MailWrist
import OutlookProvider
import Synchronization
import Testing

@testable import MailWristHost

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The watch's sign-ins come from the iPhone through iCloud Keychain, and only Gmail and Outlook make providers.
struct WristSignInsTests {
    private let device = MemoryKeychain()
    private let shared = MemoryKeychain()
    private let gmail = WristAccount(
        id: AccountID(rawValue: "g"), address: "g@gmail.com", color: .teal, unread: 0, service: .gmail)
    private let outlook = WristAccount(
        id: AccountID(rawValue: "o"), address: "o@outlook.com", color: .teal, unread: 0, service: .outlook)
    private let icloud = WristAccount(
        id: AccountID(rawValue: "i"), address: "i@icloud.com", color: .teal, unread: 0, service: .icloud)

    private let index: MailDatabase

    init() throws {
        index = try MailDatabase(
            url: FileManager.default.temporaryDirectory.appending(path: "WristSignInsTests-\(UUID().uuidString)")
                .appending(path: "mail.sqlite"))
    }

    private var signIns: WristSignIns { WristSignIns(device: device, shared: shared) }

    private func providers(http: any HTTPClient = TokenEndpoint(refreshToken: nil)) -> WristProviders {
        WristProviders(signIns: signIns, index: index, http: http)
    }

    private func share(_ token: String, for account: WristAccount, client: OAuthClient) throws {
        try shared.set(Data(token.utf8), for: client.refreshTokenKey(account.id))
    }

    @Test func gmailAndOutlookWithSignInsYieldProviders() throws {
        try share("g-token", for: gmail, client: .gmail)
        try share("o-token", for: outlook, client: .outlook)

        #expect(try signIns.held(by: [gmail, outlook, icloud]) == [gmail.id, outlook.id])
        #expect(try providers().provider(for: gmail) is GmailClient)
        #expect(try providers().provider(for: outlook) is OutlookClient)
    }

    @Test func aSignInKeptOnTheDeviceAloneServesTheAccount() throws {
        try signIns.keepOnDevice(refreshToken: "g-token", for: gmail)

        #expect(try signIns.held(by: [gmail]) == [gmail.id])
        #expect(try shared.data(for: OAuthClient.gmail.refreshTokenKey(gmail.id)) == nil)
    }

    @Test func noSignInIsKeptForAnICloudAccount() throws {
        try signIns.keepOnDevice(refreshToken: "token", for: icloud)

        #expect(try signIns.held(by: [icloud]).isEmpty)
    }

    @Test func anICloudAccountNeverDoes() throws {
        try shared.set(Data("app-password".utf8), for: "icloud.app-password.i")

        #expect(try signIns.held(by: [icloud]).isEmpty)
        #expect(try providers().provider(for: icloud) == nil)
    }

    @Test func aMissingSignInYieldsNone() throws {
        #expect(try signIns.held(by: [gmail]).isEmpty)
        #expect(try providers().provider(for: gmail) == nil)
    }

    @Test func aRefreshedMicrosoftTokenIsWrittenBackToTheSharedItem() async throws {
        try share("o-old", for: outlook, client: .outlook)
        let session = try #require(try providers(http: TokenEndpoint(refreshToken: "o-new")).session(for: outlook))

        _ = try await session.validAccessToken()

        let key = OAuthClient.outlook.refreshTokenKey(outlook.id)
        #expect(try shared.data(for: key) == Data("o-new".utf8))
        #expect(try device.data(for: key) == Data("o-new".utf8))
    }

    @Test func removingAnAccountOnTheWatchLeavesTheSharedItemAlone() throws {
        try share("g-token", for: gmail, client: .gmail)
        let key = OAuthClient.gmail.refreshTokenKey(gmail.id)
        #expect(try signIns.held(by: [gmail]) == [gmail.id], "reading keeps a device copy")

        try signIns.forget(gmail)

        #expect(try device.data(for: key) == nil)
        #expect(try shared.data(for: key) == Data("g-token".utf8))
    }

    @Test func signingOutASessionLeavesTheSharedItemAlone() async throws {
        try share("g-token", for: gmail, client: .gmail)
        let session = try #require(try providers().session(for: gmail))

        try await session.signOut()

        #expect(try shared.data(for: OAuthClient.gmail.refreshTokenKey(gmail.id)) == Data("g-token".utf8))
    }
}

/// A token endpoint that grants an access token, and rotates the refresh token when given one.
private struct TokenEndpoint: HTTPClient {
    let refreshToken: String?

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let rotated = refreshToken.map { #","refresh_token":"\#($0)""# } ?? ""
        let body = #"{"access_token":"a1","expires_in":3600\#(rotated)}"#
        return (
            Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}
