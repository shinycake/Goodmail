/// Where the reader starts moving accounts between devices by QR code: showing a code on this device, or scanning
/// another device's.
public struct TransferActions {
    /// Shows a code for another device to scan.
    public let send: () -> Void
    /// Scans the code another device shows.
    public let receive: () -> Void

    public init(send: @escaping () -> Void, receive: @escaping () -> Void) {
        self.send = send
        self.receive = receive
    }
}
