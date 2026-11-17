import SwiftUI

extension View {
    /// Makes this the control Double Tap (pinching twice) presses on Apple Watch. It does nothing elsewhere; this
    /// package also builds for iOS, so the Linux build can type-check it.
    func wristPrimaryAction() -> some View {
        #if os(watchOS)
            handGestureShortcut(.primaryAction)
        #else
            self
        #endif
    }
}
