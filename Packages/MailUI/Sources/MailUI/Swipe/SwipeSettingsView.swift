import SwiftUI

/// Which actions sit on each side of a mailbox row, and in what order. Each side and the unused actions below are one
/// reorderable collection apiece in a single reorder container, so a held row drags within its side, across to the
/// other, or down to More Actions to leave the swipes. Each row's own remove button or add menu does the same without
/// dragging. The list stays out of edit mode: UIKit keeps a row's editing controls when it moves to another section,
/// so an added action came over without its remove control.
struct SwipeSettingsView: View {
    @Bindable var model: SettingsViewModel
    /// Whether the list shows the arrangement or a drop where it fell, until that drag ends.
    @State private var listState = SwipeListState.following
    /// How many times each shelf's section was drawn again after a drop that moved nothing, as that section's
    /// identity: a new identity makes the list lay the section out afresh, where the rows really are.
    @State private var redraws: [SwipeArrangement.Shelf: Int] = [:]

    static var title: String {
        String(localized: "Swipe Actions", table: "Swipe", bundle: .module, comment: "Title of the swipe settings")
    }

    var body: some View {
        List {
            ForEach(sides, id: \.self) { side in
                Section {
                    ForEach(shelves[.side(side)]) { choice in
                        row(choice, on: .side(side), isPrimary: choice == shelves[.side(side)].first)
                    }
                    .reorderable(collectionID: SwipeArrangement.Shelf.side(side))
                    if shelves[.side(side)].isEmpty {
                        none
                    }
                } header: {
                    Text(title(of: side))
                }
                .id(redraws[.side(side), default: 0])
            }
            Section {
                ForEach(shelves[.unused]) { choice in
                    row(choice, on: .unused, isPrimary: false)
                }
                .reorderable(collectionID: SwipeArrangement.Shelf.unused)
                if shelves[.unused].isEmpty {
                    none
                }
            } header: {
                Text(
                    "More Actions", tableName: "Swipe", bundle: .module,
                    comment: "Swipe actions on neither side, waiting to be added")
            }
            .id(redraws[.unused, default: 0])
            SwipeTintsSection(model: model)
            Section {
                Button {
                    withAnimation { model.swipeArrangement = .standard }
                } label: {
                    Text(
                        "Restore Defaults", tableName: "Swipe", bundle: .module,
                        comment: "Puts the standard swipe actions back")
                }
                .disabled(model.swipeArrangement == .standard)
            } footer: {
                Text(
                    "A full swipe does the first action on its side. Each side fits up to three. Touch and hold an action to move it.",
                    tableName: "Swipe", bundle: .module, comment: "Explains the swipe settings")
            }
        }
        .reorderContainer(for: SwipeChoice.self, in: SwipeArrangement.Shelf.self) { difference in
            let anchor: SwipeChoice? =
                switch difference.destination.position {
                case .before(let choice): choice
                case .end: nil
                }
            // Not in withAnimation: the list already animates the drop, and animating it again crashed a drop at the
            // end of another section.
            listState.drop(
                difference.sources, on: difference.destination.collectionID, before: anchor,
                into: &model.swipeArrangement)
        }
        .onDragSessionUpdated { session in
            // The drop is reported before its drag ends, so the list settles back to the arrangement in an update of
            // its own.
            guard case .ended = session.phase, listState != .following else { return }
            // Without animation: a section laid out afresh would otherwise cross-fade.
            if let shelf = listState.shelfToRedraw { redraws[shelf, default: 0] += 1 }
            withAnimation { listState.dragEnded() }
        }
        .navigationTitle(Self.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// A row leads with what its control does where it sits: a side's actions come off it, the unused ones go on one.
    private func row(_ choice: SwipeChoice, on shelf: SwipeArrangement.Shelf, isPrimary: Bool) -> some View {
        HStack {
            switch shelf {
            case .side: removeButton(choice)
            case .unused: addMenu(choice)
            }
            ChoiceLabel(choice: choice, isPrimary: isPrimary)
        }
    }

    private var none: some View {
        Text("None", tableName: "Swipe", bundle: .module, comment: "A swipe settings section with no actions")
            .foregroundStyle(.secondary)
    }

    /// What each section lists: the arrangement's choices, or a drop where it fell.
    private var shelves: SwipeShelves {
        listState.shownShelves ?? SwipeShelves(model.swipeArrangement)
    }

    /// The sides in the order they sit on screen: the left one first.
    private let sides = SwipeSide.allCases

    /// A side is named by the swipe that shows it: the left side's buttons by swiping right.
    private func title(of side: SwipeSide) -> String {
        side == .left
            ? String(
                localized: "Swipe Right", table: "Swipe", bundle: .module,
                comment: "Swipe settings section: the actions a swipe to the right shows")
            : String(
                localized: "Swipe Left", table: "Swipe", bundle: .module,
                comment: "Swipe settings section: the actions a swipe to the left shows")
    }

    private func removeButton(_ choice: SwipeChoice) -> some View {
        Button {
            withAnimation { model.swipeArrangement.move([choice], to: .unused) }
        } label: {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.white, .red)
                .imageScale(.large)
                .accessibilityLabel(
                    Text(
                        "Remove \(choice.title)", tableName: "Swipe", bundle: .module,
                        comment: "Takes a swipe action off its side"))
        }
        .buttonStyle(.borderless)
    }

    private func addMenu(_ choice: SwipeChoice) -> some View {
        Menu {
            ForEach(sides, id: \.self) { side in
                Button {
                    withAnimation { model.swipeArrangement.move([choice], to: .side(side)) }
                } label: {
                    Text(
                        "Add to \(title(of: side))", tableName: "Swipe", bundle: .module,
                        comment: "Adds a swipe action to a side; the argument is that side, as Swipe Left")
                }
                .disabled(!model.swipeArrangement.hasRoom(on: side))
            }
        } label: {
            Image(systemName: "plus.circle.fill")
                .symbolRenderingMode(.multicolor)
                .imageScale(.large)
                .accessibilityLabel(
                    Text("Add \(choice.title)", tableName: "Swipe", bundle: .module, comment: "Adds a swipe action"))
        }
        .buttonStyle(.borderless)
    }
}

/// A swipe action's symbol and name, marked when a full swipe fires it.
private struct ChoiceLabel: View {
    let choice: SwipeChoice
    let isPrimary: Bool
    /// Symbols differ in width, so a shared icon width, growing with the text, lines the titles up.
    @ScaledMetric private var iconWidth = 28.0

    var body: some View {
        // Not LabeledContent: it lays a label out apart from one with no value, so titles stopped lining up.
        HStack {
            Label {
                Text(choice.title)
            } icon: {
                Image(systemName: choice.symbol).frame(width: iconWidth)
            }
            Spacer()
            if isPrimary {
                Text(
                    "Full Swipe", tableName: "Swipe", bundle: .module,
                    comment: "Marks the swipe action a full swipe fires"
                )
                .foregroundStyle(.secondary)
            }
        }
    }
}
