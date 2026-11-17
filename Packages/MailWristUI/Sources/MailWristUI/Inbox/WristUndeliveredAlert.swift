import MailCore
import MailWrist
import SwiftUI

extension View {
    /// Tells the reader when a reply sent from the watch didn't go, one at a time, with Try Again.
    func wristUndeliveredAlert(_ model: WristInboxModel) -> some View {
        modifier(WristUndeliveredAlert(model: model))
    }
}

private struct WristUndeliveredAlert: ViewModifier {
    let model: WristInboxModel

    private var shown: WristCommand? { model.undelivered.first }

    func body(content: Content) -> some View {
        content.alert(
            Text(
                "Reply Not Sent", tableName: "Wrist", bundle: .module, comment: "Alert: a reply from the watch failed"),
            // Each button settles the reply it was shown with; the next one, if any, then shows. Dismissing does
            // nothing more, so it can't touch a reply the reader hasn't seen.
            isPresented: Binding(get: { shown != nil }, set: { _ in }),
            presenting: shown
        ) { command in
            Button {
                model.resend(command)
            } label: {
                Text("Try Again", tableName: "Wrist", bundle: .module, comment: "Asks the iPhone again")
            }
            Button(role: .cancel) {
                model.forget(command)
            } label: {
                Text("OK", tableName: "Wrist", bundle: .module, comment: "Dismisses the failed reply alert")
            }
        } message: { command in
            if case .reply(let text) = command.kind {
                Text(
                    "Your iPhone couldn't send “\(text)”.", tableName: "Wrist", bundle: .module,
                    comment: "Alert: a reply from the watch failed; the reply's words")
            }
        }
    }
}
