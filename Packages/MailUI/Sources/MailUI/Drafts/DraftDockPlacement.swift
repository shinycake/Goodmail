import CoreGraphics

/// The bottom of the mail screens as the minimized messages see it, in the screens' own coordinates: where the
/// shown screen's bottom toolbar has its end buttons (Search and Compose in a mail list), and how far its content
/// ends above the bottom.
nonisolated struct BottomLine: Equatable {
    /// The width the bottom of the screens is shown across: the window's, the thread's column side by side, and off
    /// iPhone Duo's fold.
    var lane: CGRect
    /// The frames of the toolbar's end buttons, when one screen fills the window and its toolbar's middle is open.
    var ends: [CGRect]
    /// The bottom of the screens.
    var bottom: CGFloat
    /// How far the screens' content ends above `bottom`: above the toolbar, or the home indicator when there is none.
    var barsInset: CGFloat
}

/// Where the minimized messages sit over the mail screens.
nonisolated enum DraftDockPlacement: Equatable {
    /// In the middle of the bottom toolbar, between its end buttons and on their line.
    case inToolbar(CGRect)
    /// Above the toolbar, or above the home indicator when there is none.
    case floating(CGRect)

    var frame: CGRect {
        switch self {
        case .inToolbar(let frame), .floating(let frame): frame
        }
    }

    /// The least room left between the messages and a toolbar button.
    static let buttonGap: CGFloat = 12
    /// The widest the messages grow between the buttons.
    static let widestInToolbar: CGFloat = 360
    /// The narrowest they may be between the buttons; any narrower and they float above the toolbar.
    static let narrowestInToolbar: CGFloat = 120
    /// The widest they grow above the toolbar, and their room from the lane's sides and the toolbar there.
    static let widestFloating: CGFloat = 320
    static let floatingMargin: CGFloat = 16
    static let floatingGap: CGFloat = 8

    /// Between the toolbar's end buttons, centered on the lane, when `height` fits there with the gap to spare;
    /// else above the toolbar. Buttons that don't share a line are in a bar down the side, as on iPhone Duo, with no
    /// middle to sit in. Search's button reports no frame, so the room is measured from the buttons that do: centered,
    /// the messages keep the same room from both ends.
    static func choose(line: BottomLine, height: CGFloat) -> DraftDockPlacement {
        let midX = line.lane.midX
        let room = line.ends.map { $0.midX < midX ? midX - $0.maxX : $0.minX - midX }.min()
        if let first = line.ends.first, let room,
            line.ends.allSatisfy({ abs($0.midY - first.midY) < first.height / 2 })
        {
            let width = min(2 * (room - buttonGap), widestInToolbar)
            if width >= narrowestInToolbar {
                return .inToolbar(
                    CGRect(x: midX - width / 2, y: first.midY - height / 2, width: width, height: height))
            }
        }
        let width = max(min(line.lane.width - 2 * floatingMargin, widestFloating), 0)
        return .floating(
            CGRect(
                x: midX - width / 2, y: line.bottom - line.barsInset - floatingGap - height, width: width,
                height: height))
    }
}

/// What the minimized messages take of the mail screens' bottom, so the undo toast keeps clear of them.
nonisolated enum DraftDock: Equatable {
    /// No messages are minimized.
    case none
    /// They fill the middle of the bottom toolbar.
    case inToolbar
    /// They float this tall above the toolbar.
    case floating(height: CGFloat)
}
