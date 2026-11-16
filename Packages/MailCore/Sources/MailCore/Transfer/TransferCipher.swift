#if canImport(CryptoKit)
    public import CryptoKit
    import Foundation

    /// The sending side of a transfer: its code, and its half of the key both devices agree on. Accepts only a
    /// receiver that proves it scanned the code, and seals the accounts for that receiver alone.
    public struct TransferSender: Sendable {
        public enum Failure: Error, Equatable {
            /// The device that connected didn't scan this code.
            case wrongProof
            case notHello
        }

        public let invitation: TransferInvitation
        private let key: Curve25519.KeyAgreement.PrivateKey

        public init() {
            key = Curve25519.KeyAgreement.PrivateKey()
            invitation = TransferInvitation(
                service: "Goodmail-" + Self.random(8).base64URLEncodedString(),
                senderKey: key.publicKey.rawRepresentation, secret: Self.random(32))
        }

        /// `count` bytes from the system's cryptographically secure generator.
        private static func random(_ count: Int) -> Data {
            var generator = SystemRandomNumberGenerator()
            return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
        }

        /// The receiving device's name, once its `hello` proves it scanned the code.
        public func device(saying hello: TransferMessage) throws -> String {
            guard case .hello(let key, let proof, let device) = hello else { throw Failure.notHello }
            guard TransferProof.isValid(proof, of: key, secret: invitation.secret) else { throw Failure.wrongProof }
            return device
        }

        /// The accounts sealed for the device that said `hello`.
        public func seal(_ payload: TransferPayload, for hello: TransferMessage) throws -> TransferMessage {
            guard case .hello(let theirs, _, _) = hello else { throw Failure.notHello }
            let shared = try TransferProof.sharedKey(key, theirs: theirs, secret: invitation.secret)
            let sealed = try ChaChaPoly.seal(JSONEncoder().encode(payload), using: shared).combined
            return .accounts(sealed: sealed)
        }
    }

    /// The receiving side of a transfer, made from the scanned code.
    public struct TransferReceiver: Sendable {
        public enum Failure: Error, Equatable {
            /// The reader turned the transfer down on the sending device.
            case declined
            case unexpected
        }

        public let invitation: TransferInvitation
        private let key = Curve25519.KeyAgreement.PrivateKey()

        public init(invitation: TransferInvitation) {
            self.invitation = invitation
        }

        /// The first message: this device's key, proof it scanned the code, and the name the sender shows.
        public func hello(device: String) -> TransferMessage {
            let ours = key.publicKey.rawRepresentation
            return .hello(key: ours, proof: TransferProof.proof(of: ours, secret: invitation.secret), device: device)
        }

        /// The accounts in the sender's answer.
        public func open(_ answer: TransferMessage) throws -> TransferPayload {
            switch answer {
            case .accounts(let sealed):
                let shared = try TransferProof.sharedKey(key, theirs: invitation.senderKey, secret: invitation.secret)
                let data = try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: sealed), using: shared)
                return try JSONDecoder().decode(TransferPayload.self, from: data)
            case .declined: throw Failure.declined
            case .hello: throw Failure.unexpected
            }
        }
    }

    /// The keyed parts both sides share.
    enum TransferProof {
        static func proof(of key: Data, secret: Data) -> Data {
            Data(HMAC<SHA256>.authenticationCode(for: key, using: SymmetricKey(data: secret)))
        }

        static func isValid(_ proof: Data, of key: Data, secret: Data) -> Bool {
            HMAC<SHA256>.isValidAuthenticationCode(proof, authenticating: key, using: SymmetricKey(data: secret))
        }

        /// The ECDH secret stretched with the code's secret, so knowing both public keys isn't enough.
        static func sharedKey(_ ours: Curve25519.KeyAgreement.PrivateKey, theirs: Data, secret: Data) throws
            -> SymmetricKey
        {
            try ours.sharedSecretFromKeyAgreement(with: Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirs))
                .hkdfDerivedSymmetricKey(
                    using: SHA256.self, salt: secret, sharedInfo: Data("goodmail-transfer-v1".utf8),
                    outputByteCount: 32)
        }
    }
#endif
