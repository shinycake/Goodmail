import SwiftUI

/// Which actions sit on each side of a mailbox row, and in what order: a list always in edit mode, so rows reorder
/// by their handles and leave a side by their delete buttons. Actions on neither side wait below to be added.
struct SwipeSettingsView: View {
    @Bindable var model: SettingsViewModel

    static var title: String {
        String(localized: "Swipe Actions", table: "Swipe", bundle: .module, comment: "Title of the swipe settings")
    }

    var body: some View {
        List {
            ForEach(sides, id: \.self) { side in
                Section {
                    ForEach(model.swipeArrangement[side], id: \.self) { choice in
                        ChoiceLabel(choice: choice, isPrimary: choice == model.swipeArrangement[side].first)
                    }
                    .onMove { model.swipeArrangement.move(from: $0, to: $1, on: side) }
                    .onDelete { model.swipeArrangement.remove(at: $0, from: side) }
                    if model.swipeArrangement[side].isEmpty {
                        Text("None", tableName: "Swipe", bundle: .module, comment: "A swipe side with no actions")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(title(of: side))
                }
            }
            let unused = model.swipeArrangement.unused
            if !unused.isEmpty {
                Section {
                    ForEach(unused, id: \.self) { choice in
                        HStack {
                            ChoiceLabel(choice: choice, isPrimary: false)
                            Spacer()
                            addMenu(choice)
                        }
                        .deleteDisabled(true)
                        .moveDisabled(true)
                    }
                } header: {
                    Text(
                        "More Actions", tableName: "Swipe", bundle: .module,
                        comment: "Swipe actions on neither side, waiting to be added")
                }
            }
            SwipeTintsSection(model: model)
            Section {
                Button {
                    model.swipeArrangement = .standard
                } label: {
                    Text(
                        "Restore Defaults", tableName: "Swipe", bundle: .module,
                        comment: "Puts the standard swipe actions back")
                }
                .disabled(model.swipeArrangement == .standard)
            } footer: {
                Text(
                    "A full swipe does the first action on its side. Each side fits up to three.",
                    tableName: "Swipe", bundle: .module, comment: "Explains the swipe settings")
            }
        }
        .environment(\.editMode, .constant(.active))
        .navigationTitle(Self.title)
        .navigationBarTitleDisplayMode(.inline)
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

    private func addMenu(_ choice: SwipeChoice) -> some View {
        Menu {
            ForEach(sides, id: \.self) { side in
                Button {
                    withAnimation { model.swipeArrangement.add(choice, to: side) }
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
    }
}

/// A swipe action's symbol and name, marked when a full swipe fires it.
private struct ChoiceLabel: View {
    let choice: SwipeChoice
    let isPrimary: Bool

    var body: some View {
        LabeledContent {
            if isPrimary {
                Text(
                    "Full Swipe", tableName: "Swipe", bundle: .module,
                    comment: "Marks the swipe action a full swipe fires")
            }
        } label: {
            Label(choice.title, systemImage: choice.symbol)
        }
    }
}
