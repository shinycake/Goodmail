import MailCore
import UIKit

/// Links, text, pictures and files dropped on the window from another app, where nothing on it took them: they go
/// into the message being written, or start a new one, as Mail does.
extension DraftShelfViewController {
    var dropRoom: Int {
        writing?.viewModel.attachmentRoom ?? ComposeViewModel.attachmentLimit
    }

    func dropped(_ loaded: SharedItems.Loaded) {
        if let writing {
            writing.receive(loaded)
        } else {
            newMessageHolding?(loaded)
        }
    }
}
