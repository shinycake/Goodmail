import MailCore
public import SwiftUI

/// Receives accounts from another device by scanning its code, with what to do on that device at every step.
struct TransferReceiveView: View {
    let model: TransferReceiving
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            // Receiving lasts as long as the screen.
            .onDisappear { model.stop() }
            .navigationTitle(TransferReceiveView.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
    }

    static var title: Text {
        Text(
            "Transfer from Another Device", tableName: "Transfer", bundle: .module,
            comment: "Title of the screen that receives accounts from another device by QR code")
    }

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .scanning:
            Scanning { model.use($0) }
        case .connecting, .waiting:
            ContentUnavailableView {
                ProgressView()
            } description: {
                if case .waiting = model.stage {
                    Text(
                        "On your other device, choose the accounts to send here.", tableName: "Transfer",
                        bundle: .module, comment: "Shown while the sending device asks its reader to approve")
                } else {
                    Text(
                        "Finding your other device. Keep it close, with the code showing.", tableName: "Transfer",
                        bundle: .module, comment: "Shown while connecting to the device that showed the code")
                }
            }
        case .added(let accounts):
            ContentUnavailableView {
                Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.tint)
                    .accessibilityHidden(true)
            } description: {
                if accounts.isEmpty {
                    Text(
                        "Those accounts are already on this device.", tableName: "Transfer", bundle: .module,
                        comment: "Shown when every account another device sent was already here")
                } else {
                    Text(
                        "Added \(accounts.count) accounts. Their mail is on its way.", tableName: "Transfer",
                        bundle: .module, comment: "Shown after accounts arrived from another device")
                }
            } actions: {
                Button {
                    dismiss()
                } label: {
                    Text("Done", tableName: "Transfer", bundle: .module, comment: "Closes the transfer screen")
                }
                .buttonStyle(.glassProminent)
            }
        case .declined:
            again(
                symbol: "xmark.circle",
                Text(
                    "Your other device didn't send any accounts.", tableName: "Transfer", bundle: .module,
                    comment: "Shown when the sending device turned the transfer down"))
        case .failed:
            // The network's own words help nobody here; what does is moving the devices closer and trying again.
            again(
                symbol: "exclamationmark.triangle",
                Text(
                    "Couldn't reach your other device. Keep both close, with Wi-Fi and Bluetooth on, and scan its code again.",
                    tableName: "Transfer", bundle: .module, comment: "Shown when receiving accounts failed"))
        }
    }

    private func again(symbol: String, _ message: Text) -> some View {
        ContentUnavailableView {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
        } description: {
            message
        } actions: {
            Button {
                model.scanAgain()
            } label: {
                Text(
                    "Scan Again", tableName: "Transfer", bundle: .module,
                    comment: "Goes back to scanning a transfer code")
            }
            .buttonStyle(.glassProminent)
        }
    }
}

/// The camera, with what to show it.
private struct Scanning: View {
    let scanned: (URL) -> Void

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Step(
                    number: 1,
                    Text(
                        "On the device that has your accounts, open Goodmail Settings, then Other Devices.",
                        tableName: "Transfer", bundle: .module, comment: "First step of sending accounts by QR code"))
                Step(
                    number: 2,
                    Text(
                        "Tap Transfer to Another Device and unlock it.", tableName: "Transfer", bundle: .module,
                        comment: "Second step of sending accounts by QR code"))
                Step(
                    number: 3,
                    Text(
                        "Scan the code it shows.", tableName: "Transfer", bundle: .module,
                        comment: "Third step of sending accounts by QR code"))
            }
            .frame(maxWidth: 480, alignment: .leading)
            if CodeScanner.isAvailable {
                CodeScanner(accepts: TransferReceiving.isCode) { URL(string: $0).map(scanned) }
                    .clipShape(.rect(cornerRadius: 20))
            } else {
                ContentUnavailableView {
                    Image(systemName: "camera").font(.largeTitle).accessibilityHidden(true)
                } description: {
                    Text(
                        "This device can't scan here. Point its Camera app at the code instead.",
                        tableName: "Transfer", bundle: .module,
                        comment: "Shown on a device whose camera can't scan inside the app")
                }
            }
        }
        .padding(24)
    }
}

/// The screen, for UIKit to present.
public enum TransferReceiveScreen {
    public static func make(model: TransferReceiving) -> UIViewController {
        UIHostingController(rootView: NavigationStack { TransferReceiveView(model: model) })
    }
}
