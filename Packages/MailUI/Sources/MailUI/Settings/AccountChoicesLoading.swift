import SwiftUI
import UIKit

extension View {
    /// Reads `choices` as the view appears, and again each time the app comes back to the front: the reader may have
    /// turned alerts or badges on or off in iOS Settings meanwhile.
    func loads<Choice>(_ choices: AccountChoices<Choice>) -> some View {
        modifier(AccountChoicesLoading(choices: choices))
    }
}

private struct AccountChoicesLoading<Choice: Hashable & Sendable>: ViewModifier {
    let choices: AccountChoices<Choice>
    /// How often the app came back to the front while the view was up; each time starts a new read, which SwiftUI
    /// owns and cancels with the view.
    @State private var activations = 0

    func body(content: Content) -> some View {
        content
            .task(id: activations) { await choices.load() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                activations += 1
            }
    }
}
