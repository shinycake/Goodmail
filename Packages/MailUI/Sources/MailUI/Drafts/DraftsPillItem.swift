import UIKit

/// Where a pill's glass is, in some view's coordinates.
struct PillSpot {
    let pill: DraftsPillItem
    let frame: CGRect
}

/// The drafts pill: a toolbar item the system draws in glass, with the draft symbol and how many messages are
/// minimized. Hidden while there are none. Tapping it opens them.
final class DraftsPillItem {
    let item: UIBarButtonItem
    private let button = UIButton(configuration: .plain())
    private weak var site: (any DraftsPillSite)?
    private let opened: () -> Void
    /// What it shows. Zero hides the item.
    private(set) var count = 0
    /// What the only minimized message is called, which VoiceOver reads as the pill's value; `nil` with several.
    private var title: String?

    /// `dismissAll` hears Dismiss All picked in the menu a long press shows, with the pill's button.
    init(site: any DraftsPillSite, opened: @escaping () -> Void, dismissAll: @escaping (UIView) -> Void = { _ in }) {
        self.site = site
        self.opened = opened
        var configuration = UIButton.Configuration.plain()
        configuration.image = UIImage(
            systemName: "doc.text", withConfiguration: UIImage.SymbolConfiguration(textStyle: .body, scale: .medium))
        configuration.imagePlacement = .leading
        configuration.imagePadding = 6
        configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attributes = $0
            attributes.font = UIFontMetrics(forTextStyle: .body).scaledFont(
                for: .monospacedDigitSystemFont(ofSize: 17, weight: .medium))
            return attributes
        }
        button.configuration = configuration
        button.maximumContentSizeCategory = .extraExtraExtraLarge
        button.showsLargeContentViewer = true
        button.largeContentImage = configuration.image
        button.addInteraction(UILargeContentViewerInteraction())
        button.accessibilityIdentifier = "drafts.pill"
        button.accessibilityTraits = .button
        button.addAction(UIAction { _ in opened() }, for: .primaryActionTriggered)
        // A long press offers to dismiss them all; a tap still opens them.
        button.menu = UIMenu(children: [
            UIAction(
                title: String(
                    localized: "Dismiss All", table: "Drafts", bundle: .module,
                    comment: "In the drafts pill's menu: asks whether to delete or save every minimized message"),
                image: UIImage(systemName: "xmark")
            ) { [weak button] _ in button.map(dismissAll) }
        ])
        item = UIBarButtonItem(customView: button)
        item.isHidden = true
    }

    /// Whether the pill's place is on screen and still, so a card can aim at it.
    var isOnShow: Bool { site?.showsDraftsPill ?? false }

    /// Shows `count`, and `title` as the value of a pill holding one message; zero hides the pill. Only a new count
    /// touches the button, as it lays the toolbar out again.
    func show(_ count: Int, title: String? = nil) {
        self.title = title
        button.accessibilityValue = title
        guard count != self.count else { return }
        UIView.performWithoutAnimation {
            render(count)
            site?.draftsPillDidChange()
        }
    }

    /// Where the pill's glass is in `view` as it shows now, or `nil` when its place isn't on show or the toolbar
    /// hasn't placed it.
    func spot(in view: UIView) -> PillSpot? {
        guard let site, site.showsDraftsPill else { return nil }
        button.layoutIfNeeded()
        guard let frame = item.frame(in: view), DraftsPillPlacement.isPlaced(frame, in: view.bounds) else {
            return nil
        }
        let containers = sequence(first: button, next: \.superview).dropFirst().prefix(4).map {
            $0.convert($0.bounds, to: view)
        }
        return PillSpot(pill: self, frame: DraftsPillPlacement.glass(around: frame, containers: Array(containers)))
    }

    /// The icon bounces once, as a message lands in the pill.
    func bounce() {
        guard !SystemAccessibility.reducesMotion else { return }
        button.imageView?.addSymbolEffect(.bounce, options: .nonRepeating)
    }

    private func render(_ count: Int) {
        self.count = count
        let label = String(
            localized: "\(count) Drafts", table: "Drafts", bundle: .module,
            comment: "VoiceOver label of the drafts pill: how many messages are minimized")
        button.configuration?.title = count.formatted()
        button.accessibilityLabel = label
        button.accessibilityHint =
            count == 1
            ? String(
                localized: "Opens the message.", table: "Drafts", bundle: .module,
                comment: "VoiceOver hint of the drafts pill holding one message, and of a laid-out draft")
            : String(
                localized: "Shows the drafts to pick one.", table: "Drafts", bundle: .module,
                comment: "VoiceOver hint of the drafts pill holding several messages")
        button.largeContentTitle = label
        // In the toolbar's More menu when it runs short.
        item.menuRepresentation = UIAction(title: label, image: button.configuration?.image) { [opened] _ in
            opened()
        }
        item.isHidden = count == 0
    }
}
