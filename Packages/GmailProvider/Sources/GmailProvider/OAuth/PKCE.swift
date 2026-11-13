import Foundation

#if canImport(CryptoKit)
    import CryptoKit
#endif

/// Proof Key for Code Exchange (RFC 7636), so the authorization code is useless to anyone who intercepts it.
public struct PKCE: Sendable {
    public let verifier: String

    public init(verifier: String) {
        self.verifier = verifier
    }

    /// 32 random bytes, base64url-encoded: a 43-character verifier.
    public static func generate() -> PKCE {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return PKCE(verifier: Data(bytes).base64URLEncodedString())
    }

    /// The S256 challenge: base64url(SHA-256(verifier)).
    public var challenge: String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }
}
