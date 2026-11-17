import MailCore
public import MailWrist
public import SwiftUI
import WidgetKit

/// The Inbox on the watch face and in the Smart Stack: one view that takes the shape of the family it's placed in.
/// The widget extension hands it each entry of `WristGlance.timeline`.
public struct WristGlanceView: View {
    let glance: WristGlance
    @Environment(\.widgetFamily) private var family

    public init(glance: WristGlance) {
        self.glance = glance
    }

    public var body: some View {
        let shape = Shape(family)
        Group {
            switch shape {
            case .circle: WristGlanceCircle(count: glance.content.unread)
            case .line: WristGlanceLine(content: glance.content)
            case .corner: WristGlanceCorner(count: glance.content.unread)
            case .card: WristGlanceCard(content: glance.content)
            }
        }
        // The card opens the conversation it shows; a count opens the Inbox.
        .widgetURL(WristRoute.url(opening: shape == .card ? glance.content.thread : nil))
    }

    /// What the glance looks like in each family: a count in the small ones, the newest mail in the rest.
    private enum Shape {
        case circle, line, corner, card

        init(_ family: WidgetFamily) {
            switch family {
            case .accessoryCircular: self = .circle
            case .accessoryInline: self = .line
            default: self = WristGlanceCorner.fits(family) ? .corner : .card
            }
        }
    }
}

extension WristGlance.Content {
    /// The unread count, or `nil` before the iPhone has sent one.
    var unread: Int? {
        switch self {
        case .waiting: nil
        case .caughtUp: 0
        case .unread(let count, _), .code(_, _, let count): count
        }
    }
}

/// The envelope over the unread count; the envelope alone with nothing unread, and a dash before the first snapshot.
private struct WristGlanceCircle: View {
    let count: Int?

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "envelope.fill").font(.caption).widgetAccentable()
                switch count {
                case .none: Text(verbatim: "–").font(.headline)
                case .some(0): EmptyView()
                case .some(let count): Text(count, format: .number).font(.headline).minimumScaleFactor(0.5)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count.map(WristGlanceText.unread) ?? WristGlanceText.waiting)
    }
}

/// The envelope with the count and who wrote last: "3 · Noa Barak".
private struct WristGlanceLine: View {
    let content: WristGlance.Content

    var body: some View {
        Label {
            switch content {
            case .waiting: Text(verbatim: "–").accessibilityLabel(WristGlanceText.waiting)
            case .caughtUp: WristGlanceText.noUnread
            case .unread(let count, let newest), .code(_, let newest, let count):
                Text(verbatim: "\(count.formatted()) · \(newest.sender.displayName)")
            }
        } icon: {
            Image(systemName: "envelope.fill")
        }
    }
}

/// The envelope in the corner with the count along the arc.
private struct WristGlanceCorner: View {
    let count: Int?

    /// Whether `family` is the corner, which only watchOS has.
    static func fits(_ family: WidgetFamily) -> Bool {
        #if os(watchOS)
            family == .accessoryCorner
        #else
            false
        #endif
    }

    var body: some View {
        Image(systemName: "envelope.fill")
            .font(.title3)
            .widgetAccentable()
            .wristCornerLabel(WristGlanceText.unread(count).textCase(.uppercase))
    }
}

extension View {
    /// The words along a corner complication's arc. Only watchOS has the corner.
    fileprivate func wristCornerLabel(_ label: some View) -> some View {
        #if os(watchOS)
            widgetLabel { label }
        #else
            self
        #endif
    }
}

/// The glance's words, shared by the families.
enum WristGlanceText {
    static let noUnread = Text(
        "No Unread Mail", tableName: "Wrist", bundle: .module, comment: "Watch face: nothing unread")

    /// What VoiceOver says for the dash shown before the iPhone has sent anything.
    static let waiting = Text(
        "Waiting for iPhone", tableName: "Wrist", bundle: .module,
        comment: "VoiceOver, watch face: the iPhone hasn't sent the Inbox yet")

    static func unread(_ count: Int?) -> Text {
        switch count {
        case .none: Text(verbatim: "–")
        case .some(0): noUnread
        case .some(let count):
            Text(
                "\(count) Unread", tableName: "Wrist", bundle: .module,
                comment: "Above the Inbox: how many conversations are unread")
        }
    }
}
