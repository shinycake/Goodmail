import Testing
import UIKit

@testable import MailUI

@MainActor
struct ChatComposerBarLayoutTests {
    /// The height the field's constraints give it once `text` is typed at `font` (the Mac's body text is smaller than
    /// the iPhone's), with the bar docked across a phone-wide screen as the reader docks it. Frames are not read: off
    /// a window they don't follow a constraint that changes after the first layout.
    private func fieldHeight(font: UIFont? = nil, text: String = "") throws -> CGFloat {
        let screen = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 600))
        let bar = ChatComposerBar()
        bar.translatesAutoresizingMaskIntoConstraints = false
        screen.addSubview(bar)
        NSLayoutConstraint.activate([
            bar.leadingAnchor.constraint(equalTo: screen.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: screen.trailingAnchor),
            bar.bottomAnchor.constraint(equalTo: screen.bottomAnchor),
        ])
        let textView = try #require(bar.allSubviews().compactMap { $0 as? UITextView }.first)
        if let font { textView.font = font }
        screen.layoutIfNeeded()
        textView.text = text
        bar.textViewDidChange(textView)
        let send = try #require(bar.allSubviews().first { $0.accessibilityIdentifier == "chat.send" })
        let field = try #require(
            bar.allSubviews().first { ($0 as? UIVisualEffectView)?.contentView === send.superview })
        return field.systemLayoutSizeFitting(UIView.layoutFittingCompressedSize).height
    }

    /// Send is 36 points, 4 from the field's bottom; the + beside the field is 44.
    @Test(arguments: [nil, 11, 13, 15] as [CGFloat?])
    func `one line keeps the field as tall as the + beside it, with Send inside`(_ size: CGFloat?) throws {
        #expect(try fieldHeight(font: size.map { .systemFont(ofSize: $0) }, text: "See you") == 44)
    }

    @Test func `the field grows with a few lines`() throws {
        #expect(try fieldHeight(text: "One\nTwo\nThree") > 80)
    }
}

extension UIView {
    fileprivate func allSubviews() -> [UIView] {
        subviews + subviews.flatMap { $0.allSubviews() }
    }
}
