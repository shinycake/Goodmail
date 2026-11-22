import SwiftUI

/// Whether a Mac window's rows show quick actions under the pointer, and which: up to three of the swipe actions, in
/// order. Each picked action's remove button takes it off and each other one's add button puts it last; a held row
/// drags to a new place.
struct HoverSettingsView: View {
    @Bindable var model: SettingsViewModel

    static var title: String {
        String(localized: "Hover Actions", table: "Hover", bundle: .module, comment: "Title of the hover settings")
    }

    var body: some View {
        List {
            Section {
                Toggle(isOn: shows) {
                    Text(
                        "Show Hover Actions", tableName: "Hover", bundle: .module,
                        comment: "Turns the buttons a row shows under the pointer on or off")
                }
            } footer: {
                Text(
                    "Up to three actions show in the corner of the row under the pointer.", tableName: "Hover",
                    bundle: .module, comment: "Explains the hover settings")
            }
            if case .on(let picks) = model.hoverActions {
                Section {
                    ForEach(picks.choices) { choice in
                        HStack {
                            removeButton(choice, from: picks)
                            HoverChoiceLabel(choice: choice)
                        }
                    }
                    .onMove { offsets, destination in
                        model.hoverActions = .on(picks.moving(from: offsets, to: destination))
                    }
                    if picks.choices.isEmpty {
                        Text("None", tableName: "Hover", bundle: .module, comment: "No hover actions are picked")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Actions", tableName: "Hover", bundle: .module, comment: "The hover actions, in order")
                }
                Section {
                    ForEach(picks.unpicked) { choice in
                        HStack {
                            addButton(choice, to: picks)
                            HoverChoiceLabel(choice: choice)
                        }
                    }
                } header: {
                    Text(
                        "More Actions", tableName: "Hover", bundle: .module,
                        comment: "Actions the hover buttons could show, waiting to be added")
                } footer: {
                    if picks.isFull {
                        Text(
                            "Remove an action to add another.", tableName: "Hover", bundle: .module,
                            comment: "Shown when three hover actions are picked, the most there can be")
                    }
                }
            }
        }
        .navigationTitle(Self.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// On brings back the picks last chosen.
    private var shows: Binding<Bool> {
        Binding {
            model.hoverActions != .off
        } set: { isOn in
            withAnimation { model.hoverActions = isOn ? .on(Preferences.hoverActionPicks) : .off }
        }
    }

    private func removeButton(_ choice: SwipeChoice, from picks: HoverActions.Picks) -> some View {
        Button {
            withAnimation { model.hoverActions = .on(picks.removing(choice)) }
        } label: {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.white, .red)
                .imageScale(.large)
                .accessibilityLabel(
                    Text(
                        "Remove \(choice.title)", tableName: "Hover", bundle: .module,
                        comment: "Takes an action off the hover buttons"))
        }
        .buttonStyle(.borderless)
    }

    private func addButton(_ choice: SwipeChoice, to picks: HoverActions.Picks) -> some View {
        Button {
            withAnimation { model.hoverActions = .on(picks.adding(choice)) }
        } label: {
            Image(systemName: "plus.circle.fill")
                .symbolRenderingMode(.multicolor)
                .imageScale(.large)
                .accessibilityLabel(
                    Text(
                        "Add \(choice.title)", tableName: "Hover", bundle: .module,
                        comment: "Adds an action to the hover buttons"))
        }
        .buttonStyle(.borderless)
        .disabled(picks.isFull)
        // A multicolor symbol keeps its colors when disabled.
        .opacity(picks.isFull ? 0.35 : 1)
    }
}

/// An action's symbol and name.
private struct HoverChoiceLabel: View {
    let choice: SwipeChoice
    /// Symbols differ in width, so a shared icon width, growing with the text, lines the titles up.
    @ScaledMetric private var iconWidth = 28.0

    var body: some View {
        Label {
            Text(choice.title)
        } icon: {
            Image(systemName: choice.symbol).frame(width: iconWidth)
        }
    }
}
