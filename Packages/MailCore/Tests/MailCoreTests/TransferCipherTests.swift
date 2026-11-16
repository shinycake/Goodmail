#if canImport(CryptoKit)
    import Foundation
    import MailCore
    import Testing

    struct TransferCipherTests {
        private let payload = TransferPayload(entries: [
            .init(
                id: AccountID(rawValue: "g"),
                profile: SharedAccount.Profile(
                    Account(id: AccountID(rawValue: "g"), email: "me@gmail.com", color: .blue, service: .gmail),
                    position: 0),
                signIn: Data("refresh-token".utf8))
        ])

        @Test func theReceiverThatScannedTheCodeGetsTheAccounts() throws {
            let sender = TransferSender()
            let receiver = TransferReceiver(invitation: try #require(TransferInvitation(url: sender.invitation.url)))
            let hello = receiver.hello(device: "iPad")

            #expect(try sender.device(saying: hello) == "iPad")
            #expect(try receiver.open(sender.seal(payload, for: hello)) == payload)
        }

        @Test func aDeviceThatDidntScanTheCodeIsTurnedAway() throws {
            let sender = TransferSender()
            let stranger = TransferReceiver(invitation: TransferSender().invitation)

            #expect(throws: TransferSender.Failure.wrongProof) {
                try sender.device(saying: stranger.hello(device: "Not yours"))
            }
        }

        @Test func onlyTheReceiverThatSaidHelloCanOpenTheAccounts() throws {
            let sender = TransferSender()
            let receiver = TransferReceiver(invitation: sender.invitation)
            let eavesdropper = TransferReceiver(invitation: sender.invitation)
            let sealed = try sender.seal(payload, for: receiver.hello(device: "iPad"))

            #expect(throws: (any Error).self) { try eavesdropper.open(sealed) }
        }

        @Test func aDeclineReadsAsDeclined() {
            let receiver = TransferReceiver(invitation: TransferSender().invitation)
            #expect(throws: TransferReceiver.Failure.declined) { try receiver.open(.declined) }
        }
    }
#endif
