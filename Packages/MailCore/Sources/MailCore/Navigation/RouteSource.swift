/// Where a route a window follows comes from, which decides how far it may move the window.
public enum RouteSource: Equatable, Sendable {
    /// The window's own screens: a row, the sidebar, a button or a key. It moves the window only as far as it asks and
    /// dismisses nothing (R5).
    case window
    /// Outside the window: a tapped alert, Spotlight, a Shortcut, a widget, a quick action, a link or Handoff. It
    /// uncovers the window first (R3), and a conversation it opens shows in a list that holds it (R4).
    case outside
}
