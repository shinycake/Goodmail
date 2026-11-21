import MailCore
public import SwiftUI

/// Sends accounts to another device by QR code, with what to do on each device at every step.
struct TransferSendView: View {
    let model: TransferSending
    /// Bumped to start over, as with a new code after one expired.
    @State private var attempt = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content
            .navigationTitle(TransferSendView.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(role: .close) { dismiss() } }
            }
            .task(id: attempt) { await model.run() }
    }

    static var title: Text {
        Text(
            "Transfer to Another Device", tableName: "Transfer", bundle: .module,
            comment: "Title of the screen that sends accounts to another device by QR code")
    }

    @ViewBuilder private var content: some View {
        switch model.stage {
        case .unlocking, .sending:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case .locked:
            outcome(
                symbol: "lock",
                Text(
                    "Unlock to show the code. It hands over your sign-ins, so only you can show it.",
                    tableName: "Transfer", bundle: .module, comment: "Shown when Face ID or the passcode was cancelled"),
                again: Text(
                    "Try Again", tableName: "Transfer", bundle: .module,
                    comment: "Asks for Face ID or the passcode again"))
        case .showing(let code):
            CodeInstructions(code: code)
        case .choosing(let device, _):
            TransferChoice(model: model, device: device)
        case .sent(let count):
            outcome(
                symbol: "checkmark.circle",
                Text(
                    "Sent \(count) accounts. They're ready on your other device.", tableName: "Transfer",
                    bundle: .module, comment: "Shown after accounts were sent to another device"))
        case .declined:
            outcome(
                symbol: "xmark.circle",
                Text(
                    "Nothing was sent.", tableName: "Transfer", bundle: .module,
                    comment: "Shown after the reader turned a transfer down"))
        case .expired:
            outcome(
                symbol: "clock",
                Text(
                    "The code expired before another device used it.", tableName: "Transfer", bundle: .module,
                    comment: "Shown when nobody scanned the transfer code in time"),
                again: Text(
                    "Show a New Code", tableName: "Transfer", bundle: .module,
                    comment: "Starts a new transfer with a fresh code"))
        case .failed:
            outcome(
                symbol: "exclamationmark.triangle",
                Text(
                    "The transfer stopped before your other device got the accounts. Keep both close and try again.",
                    tableName: "Transfer", bundle: .module, comment: "Shown when sending accounts failed"),
                again: Text(
                    "Try Again", tableName: "Transfer", bundle: .module,
                    comment: "Starts the transfer again after it failed"))
        }
    }

    private func outcome(symbol: String, _ message: Text, again: Text? = nil) -> some View {
        ContentUnavailableView {
            Image(systemName: symbol).font(.largeTitle).foregroundStyle(.tint).accessibilityHidden(true)
        } description: {
            message
        } actions: {
            if let again {
                Button {
                    attempt += 1
                } label: {
                    again
                }
                .buttonStyle(.glassProminent)
            }
        }
    }
}

/// The code, and what to do on the other device.
private struct CodeInstructions: View {
    let code: URL

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                QRCodeView(text: code.absoluteString)
                    .frame(maxWidth: 280)
                    .accessibilityLabel(
                        Text(
                            "Transfer code", tableName: "Transfer", bundle: .module,
                            comment: "VoiceOver label of the QR code that sends accounts"))
                VStack(alignment: .leading, spacing: 12) {
                    Step(
                        number: 1,
                        Text(
                            "Open Goodmail on your other device.", tableName: "Transfer", bundle: .module,
                            comment: "First step of receiving accounts by QR code"))
                    Step(
                        number: 2,
                        Text(
                            "Tap Transfer from Another Device, or point its Camera app at this code.",
                            tableName: "Transfer", bundle: .module,
                            comment: "Second step of receiving accounts by QR code"))
                    Step(
                        number: 3,
                        Text(
                            "Choose the accounts to send here, and keep both devices close until it's done.",
                            tableName: "Transfer", bundle: .module,
                            comment: "Third step of receiving accounts by QR code"))
                }
                Label {
                    Text(
                        "This code gives access to your mail. Only show it to your own devices. It works once and expires in 5 minutes.",
                        tableName: "Transfer", bundle: .module, comment: "Warns about who sees the transfer code")
                } icon: {
                    Image(systemName: "exclamationmark.shield")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
    }
}

/// One numbered step of the instructions.
struct Step: View {
    let number: Int
    let text: Text

    init(number: Int, _ text: Text) {
        self.number = number
        self.text = text
    }

    var body: some View {
        Label {
            text
        } icon: {
            Image(systemName: "\(number).circle.fill").foregroundStyle(.tint)
        }
    }
}

/// The accounts to send the device that scanned the code, all chosen to start.
private struct TransferChoice: View {
    @Bindable var model: TransferSending
    let device: String

    var body: some View {
        List {
            Section {
                ForEach(model.accounts) { account in
                    Toggle(isOn: chosen(account.id)) { AccountLabel(account: account) }
                }
            } header: {
                Text(
                    "Send to “\(device)”?", tableName: "Transfer", bundle: .module,
                    comment: "Asks which accounts go to the device that scanned the code; the value is its name")
            } footer: {
                Text(
                    "It gets each account and its sign-in. Only send to a device you own.", tableName: "Transfer",
                    bundle: .module, comment: "Explains what sending accounts gives the other device")
            }
        }
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 12) {
                Button {
                    model.send()
                } label: {
                    Text(
                        "Send \(model.chosen.count) Accounts", tableName: "Transfer", bundle: .module,
                        comment: "Sends the chosen accounts to the other device"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .disabled(model.chosen.isEmpty)
                Button {
                    model.decline()
                } label: {
                    Text(
                        "Don't Send", tableName: "Transfer", bundle: .module,
                        comment: "Turns the other device's request down"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
            }
            .controlSize(.large)
            .frame(maxWidth: 360)
            .padding()
        }
    }

    private func chosen(_ id: AccountID) -> Binding<Bool> {
        Binding(
            get: { model.chosen.contains(id) },
            set: { isOn in
                if isOn { model.chosen.insert(id) } else { model.chosen.remove(id) }
            })
    }
}

/// The screen, for UIKit to present.
public enum TransferSendScreen {
    public static func make(model: TransferSending) -> UIViewController {
        UIHostingController(rootView: NavigationStack { TransferSendView(model: model) })
    }
}
