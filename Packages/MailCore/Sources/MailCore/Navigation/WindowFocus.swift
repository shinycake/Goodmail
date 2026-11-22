/// The app's windows in the order the reader was last in them, most recent first: the window in front, then the one
/// behind it, and so on. On the Mac a window scene can't say it, as every open window says it is key, so the app
/// follows its windows as each becomes key.
public struct WindowFocus<Window: Hashable & Sendable>: Sendable {
    /// The windows that have become key, most recent first, each once.
    private var recent: [Window] = []

    public init() {}

    /// The reader is now in `window`, among the `open` windows; the closed ones are forgotten.
    public mutating func focused(_ window: Window, open: [Window]) {
        let open = Set(open)
        recent = [window] + recent.filter { $0 != window && open.contains($0) }
    }

    /// The window the reader is in, of `windows`: the one that became key last. `nil` until one of them has.
    public func front(among windows: [Window]) -> Window? {
        recent.first(where: windows.contains)
    }

    /// `windows`, the ones the reader was in most recently first, then the rest in the order given.
    public func ordered(_ windows: [Window]) -> [Window] {
        let known = recent.filter(windows.contains)
        return known + windows.filter { !known.contains($0) }
    }
}
