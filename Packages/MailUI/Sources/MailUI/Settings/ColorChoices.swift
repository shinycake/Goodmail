import MailCore
import SwiftUI

/// Every offered account color as a swatch, then the system color picker for any other; the chosen one ringed.
struct ColorChoices: View {
    let selection: AccountColor
    let choose: (AccountColor) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(AccountColor.presets, id: \.self) { color in
                Button {
                    choose(color)
                } label: {
                    Circle()
                        .fill(Color(color.uiColor))
                        .frame(width: 32, height: 32)
                        .modifier(SwatchRing(color: Color(color.uiColor), isShown: color == selection))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(color.title))
                .accessibilityAddTraits(color == selection ? .isSelected : [])
            }
            CustomColorPicker(selection: selection, choose: choose)
        }
        .padding(.vertical, 4)
    }
}

/// The system color picker, as the last swatch. It opens on the chosen color, and shows the picked one once there is
/// one.
private struct CustomColorPicker: View {
    let selection: AccountColor
    let choose: (AccountColor) -> Void
    @Environment(\.self) private var environment

    private var picked: RGBColor? {
        if case .custom(let color) = selection { color } else { nil }
    }

    var body: some View {
        ColorPicker(
            selection: Binding(
                get: { picked.map { Color(uiColor: UIColor($0)) } ?? Color(selection.uiColor) },
                set: { choose(.custom(RGBColor($0.resolve(in: environment)))) }),
            supportsOpacity: false
        ) {
            Text(
                "Custom Color", tableName: "Theme", bundle: .module,
                comment: "An account color the reader picked with the color picker")
        }
        .labelsHidden()
        .frame(width: 32, height: 32)
        .modifier(SwatchRing(color: picked.map { Color(uiColor: UIColor($0)) } ?? .secondary, isShown: picked != nil))
        .accessibilityAddTraits(picked != nil ? .isSelected : [])
    }
}

/// A ring around a swatch when it is the chosen one, and room enough around it to tap.
struct SwatchRing: ViewModifier {
    let color: Color
    let isShown: Bool

    func body(content: Content) -> some View {
        content
            .padding(4)
            .overlay {
                if isShown { Circle().strokeBorder(color, lineWidth: 2) }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(.rect)
    }
}
