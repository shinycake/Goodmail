import MailCore
import UIKit

/// A small glass pill at the bottom of the reader. It shows where the link under the pointer goes, since mail that
/// hides a link's address is a common trick, and says that a file was saved. It never takes the pointer, or the link
/// beneath it would stop being hovered.
final class ReaderPill: UIVisualEffectView {
    enum Content: Equatable {
        case hidden
        /// A link's address, shortened in the middle.
        case link(String)
        /// A short message that goes by itself.
        case note(String)
    }

    /// How long a note stays.
    static let noteDuration = Duration.seconds(3)

    private(set) var content = Content.hidden
    private let label = UILabel()
    /// Hides the note that shows, unless something replaces it first.
    private var noteTimer: Task<Void, Never>?

    init() {
        super.init(effect: UIGlassEffect())
        cornerConfiguration = .capsule()
        isUserInteractionEnabled = false
        alpha = 0
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -6),
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Programmatic UI only") }

    deinit {
        noteTimer?.cancel()
    }

    /// The link the pointer is over, or `nil` once it leaves. A note that shows stays until its time is up.
    func hover(_ link: URL?) {
        if let link {
            show(.link(LinkAddress.shortened(link.absoluteString)))
        } else if case .link = content {
            show(.hidden)
        }
    }

    func announce(_ text: String) {
        show(.note(text))
        noteTimer = Task { [weak self] in
            try? await Task.sleep(for: Self.noteDuration)
            guard !Task.isCancelled, let self, case .note = content else { return }
            show(.hidden)
        }
    }

    /// The one place the pill changes what it shows.
    private func show(_ new: Content) {
        noteTimer?.cancel()
        noteTimer = nil
        guard new != content else { return }
        content = new
        switch new {
        case .hidden:
            break
        case .link(let address):
            label.text = address
            // An address reads left to right in any language.
            label.semanticContentAttribute = .forceLeftToRight
            label.textAlignment = .left
            accessibilityLabel = address
        case .note(let text):
            label.text = text
            label.semanticContentAttribute = .unspecified
            label.textAlignment = .natural
            accessibilityLabel = text
        }
        let visible = new != .hidden
        UIView.animate(withDuration: SystemAccessibility.reducesMotion ? 0 : 0.15) {
            self.alpha = visible ? 1 : 0
        }
    }
}
