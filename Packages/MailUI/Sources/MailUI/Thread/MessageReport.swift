import Foundation

/// What a message's script tells the app: the body's size, or the link under the pointer. The script's own world is the
/// only sender (ADR-003), and each message has one key that says which it is.
nonisolated enum MessageReport: Equatable {
    /// The body's height in points, whether it blocked remote content, and the zoom the page is at.
    case layout(height: Double, hasRemoteContent: Bool, zoom: Double)
    /// The address of the link the pointer is over, or `nil` once it leaves.
    case hover(link: URL?)

    init?(_ body: Any) {
        guard let body = body as? [String: Any] else { return nil }
        if body.keys.contains("link") {
            self = .hover(link: (body["link"] as? String).flatMap(URL.init(string:)))
        } else if let height = body["height"] as? Double {
            self = .layout(
                height: height, hasRemoteContent: body["hasRemote"] as? Bool ?? false,
                zoom: body["zoom"] as? Double ?? 1)
        } else {
            return nil
        }
    }
}
