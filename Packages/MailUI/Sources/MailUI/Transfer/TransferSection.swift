import SwiftUI

/// The Other Devices section for moving accounts by QR code, for a device that doesn't share an Apple Account with
/// this one, or when syncing is off.
struct TransferSection: View {
    let transfer: TransferActions

    var body: some View {
        Section {
            Button(action: transfer.send) {
                Label {
                    Text(
                        "Transfer to Another Device", tableName: "Transfer", bundle: .module,
                        comment: "Shows a QR code another device scans to get this device's accounts")
                } icon: {
                    Image(systemName: "qrcode")
                }
            }
            Button(action: transfer.receive) {
                Label {
                    Text(
                        "Transfer from Another Device", tableName: "Transfer", bundle: .module,
                        comment: "Scans the QR code another device shows to get its accounts")
                } icon: {
                    Image(systemName: "qrcode.viewfinder")
                }
            }
        } header: {
            Text(
                "QR Code Transfer", tableName: "Transfer", bundle: .module,
                comment: "Header of the settings for moving accounts between devices by QR code")
        } footer: {
            Text(
                "Moves accounts to a device nearby, even one signed in to a different Apple Account. Both devices need Goodmail open and to be on the same Wi-Fi or close together.",
                tableName: "Transfer", bundle: .module, comment: "Explains moving accounts by QR code")
        }
    }
}
