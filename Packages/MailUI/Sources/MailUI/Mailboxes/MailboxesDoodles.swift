import SwiftUI
import UIKit

/// Where the Mailboxes list's corner doodles sit, which the list sets as it scrolls and the doodles draw.
@Observable final class MailboxesDoodlesModel {
    var visibility = CornerDoodleVisibility.hidden
    /// The bottom of the bars at rest, where the large title ends, in the list's own coordinates.
    var barsBottom: CGFloat = 0
    /// Told whether the doodles show, so the list makes room for them after its last section or takes it back.
    @ObservationIgnored var shown: (Bool) -> Void = { _ in }
}

/// The Mailboxes list's background: a few faint, still doodles beside the large title and in the room after the
/// last section, as in Settings. They are never under a row, and they move only with the list.
struct MailboxesDoodles: View {
    let model: MailboxesDoodlesModel
    private var isDecorated = CornerDoodlesShown()

    init(model: MailboxesDoodlesModel) {
        self.model = model
    }

    var body: some View {
        let visibility = model.visibility
        ZStack(alignment: .top) {
            Color(uiColor: .systemGroupedBackground)
            if isDecorated.wrappedValue {
                // The title group's room ends where the bars do, so its doodles sit beside the large title.
                CornerDoodleGroup(doodles: CornerDoodle.mailboxesTitle)
                    .offset(y: model.barsBottom - CornerDoodleVisibility.room + visibility.titleShift)
                    .opacity(visibility.titleOpacity)
                CornerDoodleGroup(doodles: CornerDoodle.mailboxesEnd)
                    .offset(y: visibility.endTop)
                    .opacity(visibility.endOpacity)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onChange(of: isDecorated.wrappedValue, initial: true) { model.shown($1) }
    }
}

extension CornerDoodle {
    /// Beside the large title, measured down from the top of the room that ends at the bottom of the bars.
    static let mailboxesTitle: [CornerDoodle] = [
        .init(.sparkle, x: -46, y: 92, size: 12, angle: 0, tint: 1),
        .init(.ring, x: -78, y: 110, size: 7, angle: 0, tint: 2),
        .init(.at, x: -116, y: 96, size: 15, angle: -10, tint: 0),
    ]

    /// In the corners of the room after the last section.
    static let mailboxesEnd: [CornerDoodle] = [
        .init(.stamp, x: 52, y: 70, size: 34, angle: 8, tint: 1),
        .init(.squiggle, x: 112, y: 52, size: 22, angle: -6, tint: 2),
        .init(.heart, x: -150, y: 90, size: 12, angle: -12, tint: 0),
        .init(.plane, x: -66, y: 62, size: 30, angle: -8, tint: 2),
        .init(.sparkle, x: -104, y: 104, size: 11, angle: 0, tint: 1),
    ]
}

extension MailboxesViewController {
    /// Puts the doodles behind the list, which keeps them where it scrolls them.
    func installDoodles(_ model: MailboxesDoodlesModel) {
        model.shown = { [weak self] shown in
            guard let collectionView = self?.collectionView else { return }
            collectionView.contentInset.bottom = shown ? CornerDoodleVisibility.room : 0
        }
        collectionView.backgroundView = UIHostingConfiguration { MailboxesDoodles(model: model) }.margins(.all, 0)
            .makeContentView()
    }

    /// Moves the doodles with the list. The room after the last section is a bottom inset here, where in Settings it
    /// is part of the content, so the geometry is told as Settings reports it.
    func placeDoodles() {
        guard let doodles else { return }
        let room = collectionView.contentInset.bottom
        let insets = collectionView.adjustedContentInset
        let visibility = CornerDoodleVisibility(
            contentHeight: collectionView.contentSize.height + room, offset: collectionView.contentOffset.y,
            insetTop: insets.top, insetBottom: insets.bottom - room, height: collectionView.bounds.height)
        if doodles.visibility != visibility { doodles.visibility = visibility }
        // At rest, before the list has scrolled, the bars' bottom is where the content starts.
        if doodles.barsBottom != insets.top { doodles.barsBottom = insets.top }
    }
}
