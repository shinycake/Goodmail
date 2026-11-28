import MailCore

/// The `Launch` interval: from the app's first window connecting to the first mailbox list's first answer, its rows or
/// that it has none. It times a launch onto a list. A launch onto something else, as sign-in on a first run
/// or a reader restored on a phone, ends it only when a list first answers, maybe minutes later, and a launch whose
/// database fails to open never ends it.
public enum LaunchInterval {
    private static var once = Signpost.Once(.launch)

    /// Call as a window connects; only the first call starts the interval. It starts at the window rather than at
    /// `didFinishLaunching` because a launch in the background, which connects no window, finishes launching too, and
    /// with scenes the app reports itself in the background there either way.
    public static func begin() {
        once.begin()
    }

    /// A mailbox list answered for the first time. Only the first one ends the launch.
    static func end() {
        once.end()
    }
}

extension Signpost {
    static let launch = Signpost("Launch")
}
