import MailCore
import SwiftUI

/// Every account color as a swatch, the chosen one ringed.
struct ColorChoices: View {
    let selection: AccountColor
    let choose: (AccountColor) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 12)], spacing: 12) {
            ForEach(AccountColor.allCases, id: \.self) { color in
                Button {
                    choose(color)
                } label: {
                    Circle()
                        .fill(Color(color.uiColor))
                        .frame(width: 32, height: 32)
                        .padding(4)
                        .overlay {
                            if color == selection { Circle().strokeBorder(Color(color.uiColor), lineWidth: 2) }
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(color.title))
                .accessibilityAddTraits(color == selection ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}
