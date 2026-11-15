import MailCore
import SwiftUI

/// What each swipe action's button wears: clear glass, or any color from the system color picker.
struct SwipeTintsSection: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        Section {
            ForEach(SwipeChoice.allCases, id: \.self) { choice in
                SwipeTintRow(choice: choice, tint: $model.swipeTints[choice])
            }
            Button {
                model.swipeTints = .standard
            } label: {
                Text(
                    "Restore Default Colors", tableName: "Swipe", bundle: .module,
                    comment: "Puts the standard colors of the swipe actions back")
            }
            .disabled(model.swipeTints == .standard)
        } header: {
            Text("Colors", tableName: "Swipe", bundle: .module, comment: "Swipe settings section: each action's color")
        } footer: {
            Text(
                "A clear action shows the message through it, and takes the theme's color on a full swipe.",
                tableName: "Swipe", bundle: .module, comment: "Explains the Clear swipe action color")
        }
    }
}

/// One action, with a clear swatch and the color picker beside it; the one it wears ringed.
private struct SwipeTintRow: View {
    let choice: SwipeChoice
    @Binding var tint: SwipeTint
    @Environment(\.self) private var environment

    var body: some View {
        HStack {
            Label(choice.title, systemImage: choice.symbol)
            Spacer()
            Button {
                tint = .clear
            } label: {
                Circle()
                    .strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    .frame(width: 26, height: 26)
                    .modifier(SwatchRing(color: .accentColor, isShown: tint == .clear))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                Text(
                    "Make \(choice.title) Clear", tableName: "Swipe", bundle: .module,
                    comment: "Makes a swipe action's button clear glass; the argument is the action, as Archive")
            )
            .accessibilityAddTraits(tint == .clear ? .isSelected : [])
            ColorPicker(
                // A clear action's well is a neutral gray, so it never looks picked beside the clear swatch.
                selection: Binding(
                    get: { Color(uiColor: tint.fill ?? .systemGray4) },
                    set: { tint = .custom(RGBColor($0.resolve(in: environment))) }),
                supportsOpacity: false
            ) {
                Text(
                    "\(choice.title) Color", tableName: "Swipe", bundle: .module,
                    comment: "Picks the color of a swipe action's button; the argument is the action, as Archive")
            }
            .labelsHidden()
            .frame(width: 26, height: 26)
            .modifier(SwatchRing(color: .accentColor, isShown: tint != .clear))
        }
    }
}
