import DeviceCheck
import Foundation
import MailCore

/// Apple's App Attest for this install, which the push relay checks so that only this app, signed by our team, can
/// register with it (`RelayAttestation`). Unsupported on the Simulator, where requests go unsigned.
nonisolated struct AppAttestDevice: AttestationDevice {
    var isSupported: Bool { DCAppAttestService.shared.isSupported }

    func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyID, clientDataHash: clientDataHash)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyID, clientDataHash: clientDataHash)
    }
}
