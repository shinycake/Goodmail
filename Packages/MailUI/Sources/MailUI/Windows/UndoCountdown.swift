import SwiftUI
public import UIKit

/// Fills a window whose own screen is done while what it did can still be undone: a message's window after Send when
/// no mail window is open to show Undo Send, or a message window after Archive. It says what was done, counts down the
/// time left to take it back, and offers Undo, as the toast does in a mail window (`MailActions.waitOutUndo`).
public enum UndoCountdown {
    public static func make(_ toast: MailActions.Toast, undo: @escaping () -> Void) -> UIViewController {
        let left = ContinuousClock.now.duration(to: toast.ends)
        let starts = Date.now
        let seconds = Double(left.components.seconds) + Double(left.components.attoseconds) / 1e18
        let controller = UIHostingController(
            rootView: CountdownView(
                message: toast.message, time: starts...starts.addingTimeInterval(max(seconds, 0)), undo: undo))
        controller.view.backgroundColor = .systemBackground
        // Said as the toast says it in a mail window.
        SystemAccessibility.post(.announcement, argument: toast.message)
        return controller
    }
}

private struct CountdownView: View {
    let message: String
    /// From when the countdown came up to when the toast goes.
    let time: ClosedRange<Date>
    let undo: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(timerInterval: time, countsDown: true) {
                Text(message).font(.title3.weight(.semibold))
            }
            .frame(maxWidth: 280)
            Button(action: undo) {
                Text("Undo", tableName: "Actions", bundle: .module, comment: "Undoes the last action")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
