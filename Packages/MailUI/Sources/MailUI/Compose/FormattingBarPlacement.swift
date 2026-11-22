import UIKit

/// Where the composer keeps its formatting controls.
enum FormattingBarPlacement: Equatable {
    /// Above the keyboard, as the body's input accessory, while the body is being written: where the keyboard is on
    /// the screen.
    case aboveKeyboard
    /// Along the bottom of the composer's own window. A desktop window has no keyboard on the screen to ride on, and
    /// Mac Catalyst shows no input accessories at all.
    case inWindow

    init(_ style: InteractionStyle) {
        switch style {
        case .touch: self = .aboveKeyboard
        case .desktop: self = .inWindow
        }
    }
}

extension ComposeViewController {
    /// Puts the formatting bar where the window's interaction style wants it, moving it if it is elsewhere.
    func placeFormattingBar() {
        let wanted = FormattingBarPlacement(traitCollection.interactionStyle)
        guard wanted != formattingPlacement else { return }
        formattingPlacement = wanted
        switch wanted {
        case .aboveKeyboard:
            formattingBar.removeFromSuperview()
            formattingBar.translatesAutoresizingMaskIntoConstraints = true
            setScrollBottomInset(0)
            bodyView.inputAccessoryView = formattingBar
        case .inWindow:
            bodyView.inputAccessoryView = nil
            formattingBar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(formattingBar)
            NSLayoutConstraint.activate([
                formattingBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                formattingBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                formattingBar.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            ])
            // The message scrolls under the glass and its end stops clear of it.
            setScrollBottomInset(formattingBar.intrinsicContentSize.height)
        }
        bodyView.reloadInputViews()
    }
}
