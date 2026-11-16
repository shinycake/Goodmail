public import Foundation

/// What the QR code of a device sending its accounts carries: where to find it on the local network and the keys
/// that make the transfer private. It holds no sign-in. Its secret proves the receiving device saw the code, and it
/// works for one transfer only.
public struct TransferInvitation: Equatable, Sendable {
    /// The Bonjour service type both devices use.
    public static let serviceType = "_goodmail-xfer._tcp"
    /// The URL scheme of the code, which also lets the Camera app open Goodmail with it.
    public static let scheme = "goodmail-transfer"

    /// The sender's Bonjour service name, random for each transfer.
    public let service: String
    /// The sender's key agreement public key.
    public let senderKey: Data
    /// Shared only through the code: the receiver proves with it that it scanned the code.
    public let secret: Data

    public init(service: String, senderKey: Data, secret: Data) {
        self.service = service
        self.senderKey = senderKey
        self.secret = secret
    }

    /// The code's text, as `goodmail-transfer://1?s=…&k=…&c=…`.
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "1"
        components.queryItems = [
            URLQueryItem(name: "s", value: service),
            URLQueryItem(name: "k", value: senderKey.base64URLEncodedString()),
            URLQueryItem(name: "c", value: secret.base64URLEncodedString()),
        ]
        // Every part is URL-safe, so the components always make a URL.
        return components.url ?? URL(filePath: "/")
    }

    /// `nil` for anything but a code this version of the transfer reads.
    public init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme == Self.scheme, components.host == "1"
        else { return nil }
        let items = Dictionary(
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
        guard let service = items["s"], !service.isEmpty,
            let key = items["k"].flatMap(Data.init(base64URLEncoded:)), key.count == 32,
            let secret = items["c"].flatMap(Data.init(base64URLEncoded:)), secret.count == 32
        else { return nil }
        self.init(service: service, senderKey: key, secret: secret)
    }
}
