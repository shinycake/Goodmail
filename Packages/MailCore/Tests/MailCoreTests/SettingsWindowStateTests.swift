import MailCore
import Testing

struct SettingsWindowStateTests {
    /// Stands in for the window's scene session, which the state tells apart by identity.
    private final class Window {}

    @Test func `asking for Settings while it is asked for opens no second window`() {
        var state = SettingsWindowState<Window>.closed
        #expect(state.request(.main) == .open)
        #expect(state.request(.main) == .wait)
        #expect(state == .requested(.main))
    }

    @Test func `the window opens at the page asked for last`() {
        var state = SettingsWindowState<Window>.closed
        _ = state.request(.main)
        _ = state.request(.swipeActions)
        let window = Window()
        #expect(state.connected(window) == .fill(at: .swipeActions))
        #expect(state == .open(window))
    }

    @Test func `asking while it is open brings it forward at the page`() {
        var state = SettingsWindowState<Window>.closed
        let window = Window()
        #expect(state.connected(window) == .fill(at: .main), "restored by the system, unasked")
        #expect(state.request(.swipeActions) == .raise(window, at: .swipeActions))
        #expect(state == .open(window))
    }

    @Test func `a second window connecting gives way to the one open`() {
        var state = SettingsWindowState<Window>.closed
        let open = Window()
        _ = state.connected(open)
        #expect(state.connected(Window()) == .duplicate(of: open))
        #expect(state == .open(open))
    }

    @Test func `a request the system turned down can be asked again`() {
        var state = SettingsWindowState<Window>.closed
        _ = state.request(.swipeActions)
        state.requestFailed()
        #expect(state == .closed)
        #expect(state.request(.main) == .open)
    }

    @Test func `a failure after the window connected leaves it open`() {
        var state = SettingsWindowState<Window>.closed
        let window = Window()
        _ = state.connected(window)
        state.requestFailed()
        #expect(state == .open(window))
    }

    @Test func `closing the open window closes Settings, and only that window does`() {
        var state = SettingsWindowState<Window>.closed
        let window = Window()
        _ = state.connected(window)
        state.closed(Window())
        #expect(state == .open(window), "a duplicate going away")
        state.closed(window)
        #expect(state == .closed)
        #expect(state.request(.main) == .open)
    }
}
