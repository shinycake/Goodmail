import SwiftUI

/// What the pane beside the list says while a desktop window has several conversations selected: how many.
struct SelectedCountView: View {
    let count: Int

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(
                    "\(count) Conversations Selected", tableName: "Selection", bundle: .module,
                    comment: "Shown beside the list while several conversations are selected with a pointer")
            } icon: {
                Image(systemName: "square.stack")
            }
        }
    }
}
